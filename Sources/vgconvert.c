// VidGrab converter core. See vgconvert.h.
#include "vgconvert.h"

#include <stdio.h>
#include <string.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/audio_fifo.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>

static void seterr(char *err, size_t n, const char *msg, int code) {
    if (!err || !n) return;
    if (code < 0) {
        char buf[128];
        av_strerror(code, buf, sizeof buf);
        snprintf(err, n, "%s (%s)", msg, buf);
    } else {
        snprintf(err, n, "%s", msg);
    }
}

// Picks the main stream of a type, skipping cover-art images.
static int pick_stream(AVFormatContext *fmt, enum AVMediaType type) {
    int best = -1;
    int64_t bestScore = -1;
    for (unsigned i = 0; i < fmt->nb_streams; i++) {
        AVStream *s = fmt->streams[i];
        if (s->codecpar->codec_type != type) continue;
        if (s->disposition & AV_DISPOSITION_ATTACHED_PIC) continue;
        int64_t score = (int64_t)s->codecpar->width * s->codecpar->height + s->codecpar->bit_rate / 1000 + 1;
        if (score > bestScore) { bestScore = score; best = (int)i; }
    }
    return best;
}

int vg_probe(const char *path, VGProbe *out) {
    memset(out, 0, sizeof *out);
    AVFormatContext *fmt = NULL;
    if (avformat_open_input(&fmt, path, NULL, NULL) < 0) return VG_ERROR;
    if (avformat_find_stream_info(fmt, NULL) < 0) { avformat_close_input(&fmt); return VG_ERROR; }
    int v = pick_stream(fmt, AVMEDIA_TYPE_VIDEO), a = pick_stream(fmt, AVMEDIA_TYPE_AUDIO);
    if (v >= 0) snprintf(out->video, sizeof out->video, "%s", avcodec_get_name(fmt->streams[v]->codecpar->codec_id));
    if (a >= 0) snprintf(out->audio, sizeof out->audio, "%s", avcodec_get_name(fmt->streams[a]->codecpar->codec_id));
    snprintf(out->container, sizeof out->container, "%s", fmt->iformat->name);
    out->duration = fmt->duration > 0 ? fmt->duration / (double)AV_TIME_BASE : 0;
    avformat_close_input(&fmt);
    return VG_OK;
}

int vg_describe(const char *path, char *buf, size_t n) {
    if (!buf || !n) return VG_ERROR;
    buf[0] = 0;
    AVFormatContext *fmt = NULL;
    if (avformat_open_input(&fmt, path, NULL, NULL) < 0) { snprintf(buf, n, "  (FFmpeg can't open the file)\n"); return VG_ERROR; }
    avformat_find_stream_info(fmt, NULL);
    size_t used = 0;
    for (unsigned i = 0; i < fmt->nb_streams && used + 1 < n; i++) {
        AVCodecParameters *c = fmt->streams[i]->codecpar;
        const char *type = av_get_media_type_string(c->codec_type);
        char tag[8] = "";
        uint32_t t = c->codec_tag;
        if (t) {
            int printable = 1;
            for (int k = 0; k < 4; k++) { char ch = (char)(t >> (8 * k)); tag[k] = ch; if (ch < 32 || ch > 126) printable = 0; }
            tag[4] = 0;
            if (!printable) snprintf(tag, sizeof tag, "0x%x", (unsigned)(t & 0xffff));
        }
        int w = snprintf(buf + used, n - used, "  stream %u: %s %s%s%s %dx%d %lldkbps\n", i,
                         type ? type : "unknown", avcodec_get_name(c->codec_id),
                         tag[0] ? " tag=" : "", tag, c->width, c->height, (long long)(c->bit_rate / 1000));
        if (w < 0) break;
        used += (size_t)w;
    }
    if (!fmt->nb_streams) snprintf(buf, n, "  (no streams)\n");
    avformat_close_input(&fmt);
    return VG_OK;
}

// ---------------------------------------------------------------- audio re-encoding

typedef struct {
    AVCodecContext *dec, *enc;
    SwrContext *swr;
    AVAudioFifo *fifo;
    AVStream *ost;
    AVFrame *frame;
    AVPacket *opkt;
    int64_t next_pts;
} ATx;

static void atx_free(ATx *t) {
    avcodec_free_context(&t->dec);
    avcodec_free_context(&t->enc);
    swr_free(&t->swr);
    if (t->fifo) av_audio_fifo_free(t->fifo);
    t->fifo = NULL;
    av_frame_free(&t->frame);
    av_packet_free(&t->opkt);
}

static int pick_rate(const AVCodecContext *enc, const AVCodec *c, int want) {
    const int *rates = NULL;
    int n = 0;
    if (avcodec_get_supported_config(enc, c, AV_CODEC_CONFIG_SAMPLE_RATE, 0, (const void **)&rates, &n) < 0 || !rates || n <= 0)
        return want > 0 ? want : 48000;
    for (int i = 0; i < n; i++) if (rates[i] == want) return want;
    for (int i = 0; i < n; i++) if (rates[i] == 48000) return 48000;
    for (int i = 0; i < n; i++) if (rates[i] == 44100) return 44100;
    return rates[0];
}

static int atx_open(ATx *t, AVStream *ist, AVFormatContext *ofmt, int mp3, int bitrate, char *err, size_t n) {
    const AVCodec *dc = avcodec_find_decoder(ist->codecpar->codec_id);
    if (!dc) { seterr(err, n, "This audio format isn't supported", 0); return VG_ERROR; }
    t->dec = avcodec_alloc_context3(dc);
    avcodec_parameters_to_context(t->dec, ist->codecpar);
    t->dec->pkt_timebase = ist->time_base;
    int r = avcodec_open2(t->dec, dc, NULL);
    if (r < 0) { seterr(err, n, "Couldn't read the audio", r); return VG_ERROR; }
    if (t->dec->ch_layout.order == AV_CHANNEL_ORDER_UNSPEC || t->dec->ch_layout.nb_channels == 0) {
        int nch = t->dec->ch_layout.nb_channels > 0 ? t->dec->ch_layout.nb_channels : 2;
        av_channel_layout_uninit(&t->dec->ch_layout);
        av_channel_layout_default(&t->dec->ch_layout, nch);
    }

    const AVCodec *ec = mp3 ? avcodec_find_encoder_by_name("libmp3lame") : avcodec_find_encoder(AV_CODEC_ID_AAC);
    if (!ec) { seterr(err, n, "Audio encoder missing", 0); return VG_ERROR; }
    t->enc = avcodec_alloc_context3(ec);
    av_channel_layout_default(&t->enc->ch_layout, t->dec->ch_layout.nb_channels >= 2 ? 2 : 1);
    t->enc->sample_rate = pick_rate(t->enc, ec, t->dec->sample_rate);
    const enum AVSampleFormat *fmts = NULL;
    int nf = 0;
    if (avcodec_get_supported_config(t->enc, ec, AV_CODEC_CONFIG_SAMPLE_FORMAT, 0, (const void **)&fmts, &nf) >= 0 && fmts && nf > 0)
        t->enc->sample_fmt = fmts[0];
    else
        t->enc->sample_fmt = AV_SAMPLE_FMT_FLTP;
    t->enc->bit_rate = bitrate;
    t->enc->time_base = (AVRational){1, t->enc->sample_rate};
    if (ofmt->oformat->flags & AVFMT_GLOBALHEADER) t->enc->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    r = avcodec_open2(t->enc, ec, NULL);
    if (r < 0) { seterr(err, n, "Couldn't start the audio encoder", r); return VG_ERROR; }

    t->ost = avformat_new_stream(ofmt, NULL);
    avcodec_parameters_from_context(t->ost->codecpar, t->enc);
    t->ost->time_base = t->enc->time_base;

    r = swr_alloc_set_opts2(&t->swr, &t->enc->ch_layout, t->enc->sample_fmt, t->enc->sample_rate,
                            &t->dec->ch_layout, t->dec->sample_fmt, t->dec->sample_rate, 0, NULL);
    if (r < 0 || (r = swr_init(t->swr)) < 0) { seterr(err, n, "Couldn't set up audio conversion", r); return VG_ERROR; }
    t->fifo = av_audio_fifo_alloc(t->enc->sample_fmt, t->enc->ch_layout.nb_channels, 1);
    t->frame = av_frame_alloc();
    t->opkt = av_packet_alloc();
    return VG_OK;
}

static int atx_write_encoded(ATx *t, AVFormatContext *ofmt, AVFrame *f) {
    int r = avcodec_send_frame(t->enc, f);
    if (r < 0 && r != AVERROR_EOF) return r;
    while ((r = avcodec_receive_packet(t->enc, t->opkt)) == 0) {
        av_packet_rescale_ts(t->opkt, t->enc->time_base, t->ost->time_base);
        t->opkt->stream_index = t->ost->index;
        r = av_interleaved_write_frame(ofmt, t->opkt);
        if (r < 0) return r;
    }
    return (r == AVERROR(EAGAIN) || r == AVERROR_EOF) ? 0 : r;
}

static int atx_drain_fifo(ATx *t, AVFormatContext *ofmt, int final) {
    int fs = t->enc->frame_size > 0 ? t->enc->frame_size : 1024;
    while (av_audio_fifo_size(t->fifo) >= fs || (final && av_audio_fifo_size(t->fifo) > 0)) {
        int n = FFMIN(fs, av_audio_fifo_size(t->fifo));
        AVFrame *of = av_frame_alloc();
        of->nb_samples = n;
        av_channel_layout_copy(&of->ch_layout, &t->enc->ch_layout);
        of->format = t->enc->sample_fmt;
        of->sample_rate = t->enc->sample_rate;
        if (av_frame_get_buffer(of, 0) < 0) { av_frame_free(&of); return AVERROR(ENOMEM); }
        av_audio_fifo_read(t->fifo, (void **)of->data, n);
        of->pts = t->next_pts;
        t->next_pts += n;
        int r = atx_write_encoded(t, ofmt, of);
        av_frame_free(&of);
        if (r < 0) return r;
    }
    return 0;
}

static int atx_resample(ATx *t, const AVFrame *in) {
    int max_out = swr_get_out_samples(t->swr, in ? in->nb_samples : 0);
    if (max_out <= 0) return 0;
    uint8_t **buf = NULL;
    if (av_samples_alloc_array_and_samples(&buf, NULL, t->enc->ch_layout.nb_channels, max_out, t->enc->sample_fmt, 0) < 0)
        return AVERROR(ENOMEM);
    int got = swr_convert(t->swr, buf, max_out, in ? (const uint8_t **)in->extended_data : NULL, in ? in->nb_samples : 0);
    if (got > 0) av_audio_fifo_write(t->fifo, (void **)buf, got);
    av_freep(&buf[0]);
    av_freep(&buf);
    return got < 0 ? got : 0;
}

// Feeds one packet (or NULL at the end) through decode -> resample -> encode -> write.
static int atx_packet(ATx *t, AVFormatContext *ofmt, AVPacket *pkt) {
    int r = avcodec_send_packet(t->dec, pkt);
    if (r < 0 && r != AVERROR_EOF && r != AVERROR(EAGAIN)) return 0;  // skip a damaged packet
    while ((r = avcodec_receive_frame(t->dec, t->frame)) == 0) {
        r = atx_resample(t, t->frame);
        av_frame_unref(t->frame);
        if (r < 0) return r;
        if ((r = atx_drain_fifo(t, ofmt, 0)) < 0) return r;
    }
    if (!pkt) {
        atx_resample(t, NULL);
        if ((r = atx_drain_fifo(t, ofmt, 1)) < 0) return r;
        return atx_write_encoded(t, ofmt, NULL);
    }
    return 0;
}

// ---------------------------------------------------------------- output helpers

static int open_output(AVFormatContext **ofmt, const char *format, const char *out, char *err, size_t n) {
    int r = avformat_alloc_output_context2(ofmt, NULL, format, out);
    if (r < 0 || !*ofmt) { seterr(err, n, "Couldn't create the output file", r); return VG_ERROR; }
    return VG_OK;
}

static int start_output(AVFormatContext *ofmt, const char *out, int mp4, char *err, size_t n) {
    int r;
    if (!(ofmt->oformat->flags & AVFMT_NOFILE) && (r = avio_open(&ofmt->pb, out, AVIO_FLAG_WRITE)) < 0) {
        seterr(err, n, "Couldn't write the output file", r);
        return VG_ERROR;
    }
    AVDictionary *opts = NULL;
    if (mp4) av_dict_set(&opts, "movflags", "+faststart", 0);
    else av_dict_set(&opts, "id3v2_version", "3", 0);
    r = avformat_write_header(ofmt, &opts);
    av_dict_free(&opts);
    if (r < 0) { seterr(err, n, "Couldn't start writing the file", r); return VG_ERROR; }
    return VG_OK;
}

static void close_output(AVFormatContext **ofmt) {
    if (!*ofmt) return;
    if (!((*ofmt)->oformat->flags & AVFMT_NOFILE)) avio_closep(&(*ofmt)->pb);
    avformat_free_context(*ofmt);
    *ofmt = NULL;
}

static double clamp01(double x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }

// ---------------------------------------------------------------- audio file

int vg_audio(const char *in, const char *out, int mp3, int bitrate, const char *title, const char *artist,
             vg_progress_cb progress, vg_cancel_cb cancel, void *ctx, char *err, size_t errlen) {
    AVFormatContext *ifmt = NULL, *ofmt = NULL;
    AVPacket *pkt = NULL;
    ATx t;
    memset(&t, 0, sizeof t);
    int ret = VG_ERROR, r, started = 0;

    if ((r = avformat_open_input(&ifmt, in, NULL, NULL)) < 0) { seterr(err, errlen, "Couldn't open the downloaded file", r); goto end; }
    avformat_find_stream_info(ifmt, NULL);
    int ai = pick_stream(ifmt, AVMEDIA_TYPE_AUDIO);
    if (ai < 0) { seterr(err, errlen, "This file has no sound to convert", 0); goto end; }
    AVStream *ist = ifmt->streams[ai];

    if (open_output(&ofmt, mp3 ? "mp3" : "ipod", out, err, errlen) != VG_OK) goto end;
    if (atx_open(&t, ist, ofmt, mp3, bitrate, err, errlen) != VG_OK) goto end;
    if (title && *title) av_dict_set(&ofmt->metadata, "title", title, 0);
    if (artist && *artist) av_dict_set(&ofmt->metadata, "artist", artist, 0);
    if (start_output(ofmt, out, !mp3, err, errlen) != VG_OK) goto end;
    started = 1;

    pkt = av_packet_alloc();
    double dur = ifmt->duration > 0 ? ifmt->duration / (double)AV_TIME_BASE : 0;
    int64_t start = ist->start_time != AV_NOPTS_VALUE ? ist->start_time : 0;
    while ((r = av_read_frame(ifmt, pkt)) >= 0) {
        if (cancel && cancel(ctx)) { av_packet_unref(pkt); ret = VG_CANCELLED; goto end; }
        if (pkt->stream_index == ai) {
            if (progress && dur > 0 && pkt->pts != AV_NOPTS_VALUE)
                progress(ctx, clamp01((pkt->pts - start) * av_q2d(ist->time_base) / dur));
            if ((r = atx_packet(&t, ofmt, pkt)) < 0) { seterr(err, errlen, "Audio conversion failed", r); av_packet_unref(pkt); goto end; }
        }
        av_packet_unref(pkt);
    }
    if ((r = atx_packet(&t, ofmt, NULL)) < 0) { seterr(err, errlen, "Audio conversion failed", r); goto end; }
    if ((r = av_write_trailer(ofmt)) < 0) { seterr(err, errlen, "Couldn't finish the file", r); goto end; }
    started = 0;
    if (progress) progress(ctx, 1.0);
    ret = VG_OK;

end:
    if (started && ofmt) av_write_trailer(ofmt);
    atx_free(&t);
    av_packet_free(&pkt);
    avformat_close_input(&ifmt);
    close_output(&ofmt);
    if (ret != VG_OK) remove(out);
    return ret;
}

// ---------------------------------------------------------------- video to MP4

// MKV/WebM store only presentation times. MP4 also needs decode-order times; they are
// rebuilt here: the k-th packet in decode order gets the k-th smallest presentation time.
#define VG_REORDER 16
typedef struct {
    AVPacket *q[VG_REORDER + 1];
    int qn;
    int64_t pts[VG_REORDER + 1];
    int pn;
    int64_t delay;     // how far decode time runs ahead of display time (B-frames)
    int delayKnown;
    int64_t lastDts;
} Reorder;

static int64_t reorder_pop_min(Reorder *r) {
    int mi = 0;
    for (int i = 1; i < r->pn; i++) if (r->pts[i] < r->pts[mi]) mi = i;
    int64_t v = r->pts[mi];
    r->pts[mi] = r->pts[--r->pn];
    return v;
}

static int cmp64(const void *a, const void *b) {
    int64_t x = *(const int64_t *)a, y = *(const int64_t *)b;
    return x < y ? -1 : x > y;
}

// Writes one copied packet (video or audio) to the MP4.
static int write_copied(AVFormatContext *ofmt, AVPacket *pkt, AVStream *is, AVStream *os) {
    av_packet_rescale_ts(pkt, is->time_base, os->time_base);
    pkt->stream_index = os->index;
    pkt->pos = -1;
    return av_interleaved_write_frame(ofmt, pkt);
}

static int reorder_write_front(Reorder *r, AVFormatContext *ofmt, AVStream *is, AVStream *os) {
    if (!r->delayKnown) {
        // From the buffered window: the k-th packet in decode order must not be decoded
        // after it is shown, so decode time = (k-th smallest display time) - delay.
        int64_t sorted[VG_REORDER + 1];
        int n = r->pn;
        memcpy(sorted, r->pts, sizeof(int64_t) * (size_t)n);
        qsort(sorted, (size_t)n, sizeof(int64_t), cmp64);
        r->delay = 0;
        for (int i = 0; i < r->qn && i < n; i++) {
            int64_t lag = sorted[i] - r->q[i]->pts;
            if (lag > r->delay) r->delay = lag;
        }
        r->delayKnown = 1;
        r->lastDts = INT64_MIN;
    }
    AVPacket *c = r->q[0];
    memmove(r->q, r->q + 1, sizeof(AVPacket *) * (size_t)(r->qn - 1));
    r->qn--;
    int64_t dts = reorder_pop_min(r) - r->delay;
    if (dts > c->pts) dts = c->pts;
    if (r->lastDts != INT64_MIN && dts <= r->lastDts) dts = r->lastDts + 1;
    r->lastDts = dts;
    c->dts = dts;
    int ret = write_copied(ofmt, c, is, os);
    av_packet_free(&c);
    return ret;
}

// One input file being read; keeps the next useful packet ready ("peek").
typedef struct {
    AVFormatContext *fmt;
    AVPacket *peek;
    int has, eof, want1, want2;
    int64_t start;
} Src;

static void src_fill(Src *s) {
    while (!s->eof && !s->has) {
        if (av_read_frame(s->fmt, s->peek) < 0) { s->eof = 1; break; }
        int si = s->peek->stream_index;
        if (si == s->want1 || si == s->want2) s->has = 1;
        else av_packet_unref(s->peek);
    }
}

static double src_time(Src *s) {
    AVStream *st = s->fmt->streams[s->peek->stream_index];
    int64_t t = s->peek->dts != AV_NOPTS_VALUE ? s->peek->dts : s->peek->pts;
    if (t == AV_NOPTS_VALUE) return 0;
    return (t - av_rescale_q(s->start, AV_TIME_BASE_Q, st->time_base)) * av_q2d(st->time_base);
}

static int open_src(Src *s, const char *path, char *err, size_t errlen) {
    int r;
    s->want1 = s->want2 = -1;
    if ((r = avformat_open_input(&s->fmt, path, NULL, NULL)) < 0) { seterr(err, errlen, "Couldn't open the downloaded file", r); return VG_ERROR; }
    if ((r = avformat_find_stream_info(s->fmt, NULL)) < 0) { seterr(err, errlen, "Couldn't read the downloaded file", r); return VG_ERROR; }
    s->start = s->fmt->start_time != AV_NOPTS_VALUE ? s->fmt->start_time : 0;
    s->peek = av_packet_alloc();
    return VG_OK;
}

static void close_src(Src *s) {
    av_packet_free(&s->peek);
    avformat_close_input(&s->fmt);
}

int vg_mux_mp4(const char *videoIn, const char *audioIn, const char *out, vg_progress_cb progress, vg_cancel_cb cancel,
               void *ctx, char *err, size_t errlen) {
    AVFormatContext *ofmt = NULL;
    Src src[2];
    memset(src, 0, sizeof src);
    int nsrc = 0;
    ATx t;
    memset(&t, 0, sizeof t);
    int ret = VG_ERROR, r, started = 0, audioCopy = 0, audioTx = 0, writeErrors = 0;
    AVStream *ovs = NULL, *oas = NULL;
    Reorder ro;
    memset(&ro, 0, sizeof ro);

    // Source 0 gives the video. The sound comes from audioIn if given, otherwise from the same file.
    if (open_src(&src[0], videoIn, err, errlen) != VG_OK) { nsrc = 1; goto end; }
    nsrc = 1;
    int vi = pick_stream(src[0].fmt, AVMEDIA_TYPE_VIDEO);
    if (vi < 0) { seterr(err, errlen, "This file has no video", 0); goto end; }
    src[0].want1 = vi;
    Src *asrc = NULL;
    int ai = -1;
    if (audioIn && *audioIn) {
        if (open_src(&src[1], audioIn, err, errlen) != VG_OK) { nsrc = 2; goto end; }
        nsrc = 2;
        ai = pick_stream(src[1].fmt, AVMEDIA_TYPE_AUDIO);
        if (ai >= 0) { asrc = &src[1]; src[1].want1 = ai; }
    } else {
        ai = pick_stream(src[0].fmt, AVMEDIA_TYPE_AUDIO);
        if (ai >= 0) { asrc = &src[0]; src[0].want2 = ai; }
    }

    AVStream *ivs = src[0].fmt->streams[vi];
    enum AVCodecID vid = ivs->codecpar->codec_id;
    if (vid != AV_CODEC_ID_H264 && vid != AV_CODEC_ID_HEVC) { seterr(err, errlen, "This video needs full converting", 0); goto end; }

    if (open_output(&ofmt, "mp4", out, err, errlen) != VG_OK) goto end;
    ovs = avformat_new_stream(ofmt, NULL);
    avcodec_parameters_copy(ovs->codecpar, ivs->codecpar);
    ovs->codecpar->codec_tag = (vid == AV_CODEC_ID_HEVC) ? MKTAG('h', 'v', 'c', '1') : 0;  // hvc1 is what Apple expects
    ovs->time_base = ivs->time_base;

    if (asrc) {
        AVStream *ias = asrc->fmt->streams[ai];
        if (ias->codecpar->codec_id == AV_CODEC_ID_AAC) {
            oas = avformat_new_stream(ofmt, NULL);
            avcodec_parameters_copy(oas->codecpar, ias->codecpar);
            oas->codecpar->codec_tag = 0;
            oas->time_base = ias->time_base;
            audioCopy = 1;
        } else {
            if (atx_open(&t, ias, ofmt, 0, 192000, err, errlen) != VG_OK) goto end;
            audioTx = 1;
        }
    }
    if (start_output(ofmt, out, 1, err, errlen) != VG_OK) goto end;
    started = 1;

    double dur = src[0].fmt->duration > 0 ? src[0].fmt->duration / (double)AV_TIME_BASE : 0;
    int synth = -1;  // decided on the first video packet: 1 if the file has no decode times
    while (1) {
        if (cancel && cancel(ctx)) { ret = VG_CANCELLED; goto end; }
        for (int k = 0; k < nsrc; k++) src_fill(&src[k]);
        // Take the earliest packet across the inputs so video and sound stay interleaved.
        Src *s = NULL;
        for (int k = 0; k < nsrc; k++) if (src[k].has && (!s || src_time(&src[k]) < src_time(s))) s = &src[k];
        if (!s) break;
        AVPacket *pkt = s->peek;
        s->has = 0;
        int si = pkt->stream_index;
        int isVideo = (s == &src[0] && si == vi);
        int isAudio = (s == asrc && si == ai);
        AVStream *is = s->fmt->streams[si];

        if (isVideo || (isAudio && audioCopy)) {
            AVStream *os = isVideo ? ovs : oas;
            if (pkt->pts == AV_NOPTS_VALUE && pkt->dts == AV_NOPTS_VALUE) { av_packet_unref(pkt); continue; }
            int64_t off = av_rescale_q(s->start, AV_TIME_BASE_Q, is->time_base);
            if (pkt->pts != AV_NOPTS_VALUE) pkt->pts -= off;
            if (pkt->dts != AV_NOPTS_VALUE) pkt->dts -= off;
            if (isVideo) {
                if (progress && dur > 0 && pkt->pts != AV_NOPTS_VALUE)
                    progress(ctx, clamp01(pkt->pts * av_q2d(is->time_base) / dur));
                // MKV/WebM only store presentation times (FFmpeg guesses decode times that break
                // B-frames), so always rebuild them there. Other containers keep their own.
                if (synth < 0) synth = (pkt->dts == AV_NOPTS_VALUE || !strncmp(s->fmt->iformat->name, "matroska", 8)) ? 1 : 0;
                if (synth) {
                    if (pkt->pts == AV_NOPTS_VALUE) { av_packet_unref(pkt); continue; }
                    AVPacket *c = av_packet_alloc();
                    av_packet_move_ref(c, pkt);
                    ro.q[ro.qn++] = c;
                    ro.pts[ro.pn++] = c->pts;
                    if (ro.qn > VG_REORDER && reorder_write_front(&ro, ofmt, is, os) < 0 && ++writeErrors > 200) {
                        seterr(err, errlen, "Too many damaged pieces in this video", 0);
                        goto end;
                    }
                    continue;
                }
            }
            if (write_copied(ofmt, pkt, is, os) < 0 && ++writeErrors > 200) {
                seterr(err, errlen, "Too many damaged pieces in this video", 0);
                goto end;
            }
        } else if (isAudio && audioTx) {
            if ((r = atx_packet(&t, ofmt, pkt)) < 0) { seterr(err, errlen, "Audio conversion failed", r); av_packet_unref(pkt); goto end; }
        }
        av_packet_unref(pkt);
    }
    while (ro.qn > 0) reorder_write_front(&ro, ofmt, src[0].fmt->streams[vi], ovs);
    if (audioTx && (r = atx_packet(&t, ofmt, NULL)) < 0) { seterr(err, errlen, "Audio conversion failed", r); goto end; }
    if ((r = av_write_trailer(ofmt)) < 0) { seterr(err, errlen, "Couldn't finish the MP4", r); goto end; }
    started = 0;
    if (progress) progress(ctx, 1.0);
    ret = VG_OK;

end:
    if (started && ofmt) av_write_trailer(ofmt);
    for (int i = 0; i < ro.qn; i++) av_packet_free(&ro.q[i]);
    atx_free(&t);
    for (int k = 0; k < 2; k++) if (src[k].fmt || src[k].peek) close_src(&src[k]);
    close_output(&ofmt);
    if (ret != VG_OK) remove(out);
    return ret;
}

int vg_remux_mp4(const char *in, const char *out, vg_progress_cb progress, vg_cancel_cb cancel, void *ctx,
                 char *err, size_t errlen) {
    return vg_mux_mp4(in, NULL, out, progress, cancel, ctx, err, errlen);
}
