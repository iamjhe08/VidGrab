// VidGrab converter core. See vgconvert.h.
#include "vgconvert.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
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

// FFmpeg normally looks at the first 5 MB (and 5 s) of a file to learn what is in it. Pieces of HLS video can start
// with sound only, or have their first keyframe far in, so the video routines look at up to 20 MB / 10 s.
// It stops as soon as it has what it needs, so normal files aren't slower. (Audio-only routines keep the default.)
static int open_input_probe(AVFormatContext **fmt, const char *path) {
    AVDictionary *o = NULL;
    av_dict_set(&o, "probesize", "20000000", 0);
    av_dict_set(&o, "analyzeduration", "10000000", 0);
    int r = avformat_open_input(fmt, path, NULL, &o);
    av_dict_free(&o);
    return r;
}

int vg_probe(const char *path, VGProbe *out) {
    memset(out, 0, sizeof *out);
    AVFormatContext *fmt = NULL;
    if (open_input_probe(&fmt, path) < 0) return VG_ERROR;
    if (avformat_find_stream_info(fmt, NULL) < 0) { avformat_close_input(&fmt); return VG_ERROR; }
    int v = pick_stream(fmt, AVMEDIA_TYPE_VIDEO), a = pick_stream(fmt, AVMEDIA_TYPE_AUDIO);
    if (v >= 0) {
        snprintf(out->video, sizeof out->video, "%s", avcodec_get_name(fmt->streams[v]->codecpar->codec_id));
        out->width = fmt->streams[v]->codecpar->width;
        out->height = fmt->streams[v]->codecpar->height;
    }
    if (a >= 0) snprintf(out->audio, sizeof out->audio, "%s", avcodec_get_name(fmt->streams[a]->codecpar->codec_id));
    snprintf(out->container, sizeof out->container, "%s", fmt->iformat->name);
    out->duration = fmt->duration > 0 ? fmt->duration / (double)AV_TIME_BASE : 0;
    avformat_close_input(&fmt);
    return VG_OK;
}

static const char *ts_type_name(int t) {
    switch (t) {
        case 0x01: return "MPEG-1 video"; case 0x02: return "MPEG-2 video"; case 0x03: return "MPEG-1 audio";
        case 0x04: return "MPEG-2 audio"; case 0x06: return "private data"; case 0x0f: return "AAC";
        case 0x11: return "AAC-LATM"; case 0x15: return "metadata"; case 0x1b: return "H.264"; case 0x24: return "HEVC";
        case 0x81: return "AC-3"; case 0x82: return "DTS"; case 0x86: return "DTS-HD"; case 0x87: return "E-AC-3";
        case 0xdb: return "H.264 SAMPLE-AES (encrypted)"; case 0xcf: return "AAC SAMPLE-AES (encrypted)";
        case 0xc1: return "AC-3 SAMPLE-AES (encrypted)"; case 0xc2: return "E-AC-3 SAMPLE-AES (encrypted)";
        default: return "unknown";
    }
}

static const char *ts_pes_name(int id) {
    if (id >= 0xe0 && id <= 0xef) return "video";
    if (id >= 0xc0 && id <= 0xdf) return "audio";
    if (id == 0xbd) return "private-1";
    if (id == 0xbf) return "private-2";
    return "other";
}

int vg_ts_scan(const char *path, char *buf, size_t n, long *scrambled, int *isTS) {
    enum { SCAN_BYTES = 6 * 1024 * 1024 };
    if (scrambled) *scrambled = 0;
    if (isTS) *isTS = 0;
    if (!buf || !n) return VG_ERROR;
    buf[0] = 0;
    FILE *f = fopen(path, "rb");
    if (!f) { snprintf(buf, n, "  ts: can't open the file\n"); return VG_ERROR; }
    unsigned char *d = malloc(SCAN_BYTES);
    if (!d) { fclose(f); return VG_ERROR; }
    size_t len = fread(d, 1, SCAN_BYTES, f);
    fclose(f);

    int psz = 0; size_t off = 0;
    static const int sizes[3] = {188, 192, 204};
    for (int si = 0; si < 3 && !psz; si++) {
        size_t sz = (size_t)sizes[si];
        for (size_t o = 0; o < sz && o + sz * 6 < len && !psz; o++) {
            int ok = 1;
            for (size_t k = 0; k < 6; k++) if (d[o + sz * k] != 0x47) { ok = 0; break; }
            if (ok) { psz = sizes[si]; off = o; }
        }
    }
    if (!psz) {
        snprintf(buf, n, "  ts: not MPEG-TS (no repeating 0x47 sync bytes); first bytes %02x %02x %02x %02x %02x %02x %02x %02x\n",
                 len > 0 ? d[0] : 0, len > 1 ? d[1] : 0, len > 2 ? d[2] : 0, len > 3 ? d[3] : 0,
                 len > 4 ? d[4] : 0, len > 5 ? d[5] : 0, len > 6 ? d[6] : 0, len > 7 ? d[7] : 0);
        free(d);
        return VG_OK;
    }
    if (isTS) *isTS = 1;

    long pidCount[8192], pidScr[8192];
    short pidPes[8192];
    memset(pidCount, 0, sizeof pidCount); memset(pidScr, 0, sizeof pidScr);
    for (int i = 0; i < 8192; i++) pidPes[i] = -1;
    int pmtPid[8] = {0}, pmtN = 0;
    struct { int pid, type; } es[24];
    int esN = 0;
    long total = 0, bad = 0, scr = 0;

    for (size_t pos = off; pos + (size_t)psz <= len; pos += (size_t)psz) {
        const unsigned char *p = d + pos;
        if (p[0] != 0x47) { bad++; continue; }
        int pid = ((p[1] & 0x1f) << 8) | p[2];
        int pusi = (p[1] & 0x40) != 0;
        int sc = p[3] >> 6;
        int afc = (p[3] >> 4) & 3;
        size_t po = 4;
        if (afc & 2) po = 5 + p[4];
        if (!(afc & 1) || po >= 188) continue;
        total++;
        pidCount[pid]++;
        if (sc >= 2 && pid > 0x1f) { pidScr[pid]++; scr++; continue; }
        const unsigned char *pl = p + po;
        size_t pn = 188 - po;
        if (pid == 0 && pusi && pn > 12) {
            const unsigned char *sec = pl + 1 + pl[0];
            if (sec + 12 < p + 188 && sec[0] == 0) {
                int sl = ((sec[1] & 0xf) << 8) | sec[2];
                const unsigned char *e = sec + 8, *end = sec + 3 + sl - 4;
                for (; e + 4 <= end && e + 4 <= p + 188 && pmtN < 8; e += 4) {
                    int prog = (e[0] << 8) | e[1];
                    int mp = ((e[2] & 0x1f) << 8) | e[3];
                    if (prog) { int dup = 0; for (int k = 0; k < pmtN; k++) if (pmtPid[k] == mp) dup = 1; if (!dup) pmtPid[pmtN++] = mp; }
                }
            }
            continue;
        }
        int isPmt = 0;
        for (int k = 0; k < pmtN; k++) if (pmtPid[k] == pid) isPmt = 1;
        if (isPmt && pusi && pn > 16) {
            const unsigned char *sec = pl + 1 + pl[0];
            if (sec + 12 < p + 188 && sec[0] == 2) {
                int sl = ((sec[1] & 0xf) << 8) | sec[2];
                int pil = ((sec[10] & 0xf) << 8) | sec[11];
                const unsigned char *e = sec + 12 + pil, *end = sec + 3 + sl - 4;
                while (e + 5 <= end && e + 5 <= p + 188 && esN < 24) {
                    int type = e[0], epid = ((e[1] & 0x1f) << 8) | e[2], il = ((e[3] & 0xf) << 8) | e[4];
                    int dup = 0;
                    for (int k = 0; k < esN; k++) if (es[k].pid == epid) dup = 1;
                    if (!dup) { es[esN].pid = epid; es[esN].type = type; esN++; }
                    e += 5 + il;
                }
            }
            continue;
        }
        if (pusi && pn >= 4 && pl[0] == 0 && pl[1] == 0 && pl[2] == 1 && pidPes[pid] < 0) pidPes[pid] = pl[3];
    }

    size_t used = 0;
    #define OUT(...) do { if (used + 1 < n) { int w_ = snprintf(buf + used, n - used, __VA_ARGS__); if (w_ > 0) used += (size_t)w_; } } while (0)
    OUT("  ts: %ld packets read, %ld out of step, %ld scrambled\n", total, bad, scr);
    for (int k = 0; k < esN; k++)
        OUT("  ts: declared pid 0x%x type 0x%02x (%s)%s%s\n", es[k].pid, es[k].type, ts_type_name(es[k].type),
            pidPes[es[k].pid] >= 0 ? ", data starts as " : ", no data seen",
            pidPes[es[k].pid] >= 0 ? ts_pes_name(pidPes[es[k].pid]) : "");
    // The busiest PIDs that carry data, whether or not they are declared.
    for (int shown = 0; shown < 6; shown++) {
        int best = -1;
        for (int pid = 0x20; pid < 0x1fff; pid++) {
            if (pidCount[pid] <= 0) continue;
            int skip = 0;
            for (int k = 0; k < pmtN; k++) if (pmtPid[k] == pid) skip = 1;
            if (skip) continue;
            if (best < 0 || pidCount[pid] > pidCount[best]) best = pid;
        }
        if (best < 0) break;
        OUT("  ts: pid 0x%x: %ld packets%s%s%s%ld scrambled)\n", best, pidCount[best],
            pidPes[best] >= 0 ? ", " : "", pidPes[best] >= 0 ? ts_pes_name(pidPes[best]) : "", " (", pidScr[best]);
        pidCount[best] = -pidCount[best];
    }
    #undef OUT
    if (scrambled) *scrambled = scr;
    free(d);
    return VG_OK;
}

int vg_describe(const char *path, char *buf, size_t n) {
    if (!buf || !n) return VG_ERROR;
    buf[0] = 0;
    AVFormatContext *fmt = NULL;
    if (open_input_probe(&fmt, path) < 0) { snprintf(buf, n, "  (FFmpeg can't open the file)\n"); return VG_ERROR; }
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
    AVChannelLayout in_layout;      // what the resampler is currently set up for
    int in_rate;
    enum AVSampleFormat in_fmt;
    long frames;                    // sound frames the decoder really produced
} ATx;

static void atx_free(ATx *t) {
    avcodec_free_context(&t->dec);
    avcodec_free_context(&t->enc);
    swr_free(&t->swr);
    av_channel_layout_uninit(&t->in_layout);
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
    if (!dc) {
        char m[96];
        snprintf(m, sizeof m, "VidGrab can't convert %s sound to AAC", avcodec_get_name(ist->codecpar->codec_id));
        seterr(err, n, m, 0);
        return VG_ERROR;
    }
    t->dec = avcodec_alloc_context3(dc);
    avcodec_parameters_to_context(t->dec, ist->codecpar);
    t->dec->pkt_timebase = ist->time_base;
    int r = avcodec_open2(t->dec, dc, NULL);
    if (r < 0) { seterr(err, n, "Couldn't read the audio", r); return VG_ERROR; }
    if (t->dec->sample_rate <= 0) { seterr(err, n, "Couldn't read the sound's settings", 0); return VG_ERROR; }
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
    av_channel_layout_copy(&t->in_layout, &t->dec->ch_layout);
    t->in_rate = t->dec->sample_rate;
    t->in_fmt = t->dec->sample_fmt;
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

// If the decoder starts giving sound in a different format than it was opened with (damaged or mis-detected
// streams do this), the resampler is rebuilt for what is really arriving instead of reading the wrong buffers.
static int atx_reconfigure(ATx *t, const AVFrame *f) {
    atx_resample(t, NULL);                       // let out what the old setup still holds
    swr_free(&t->swr);
    AVChannelLayout lay = {0};
    av_channel_layout_copy(&lay, &f->ch_layout);
    if (lay.order == AV_CHANNEL_ORDER_UNSPEC || lay.nb_channels == 0) {
        int nch = lay.nb_channels > 0 ? lay.nb_channels : 2;
        av_channel_layout_uninit(&lay);
        av_channel_layout_default(&lay, nch);
    }
    int r = swr_alloc_set_opts2(&t->swr, &t->enc->ch_layout, t->enc->sample_fmt, t->enc->sample_rate,
                                &lay, (enum AVSampleFormat)f->format, f->sample_rate, 0, NULL);
    if (r >= 0) r = swr_init(t->swr);
    av_channel_layout_uninit(&lay);
    if (r < 0) return r;
    av_channel_layout_uninit(&t->in_layout);
    av_channel_layout_copy(&t->in_layout, &f->ch_layout);
    t->in_rate = f->sample_rate;
    t->in_fmt = (enum AVSampleFormat)f->format;
    return 0;
}

// Feeds one packet (or NULL at the end) through decode -> resample -> encode -> write.
static int atx_packet(ATx *t, AVFormatContext *ofmt, AVPacket *pkt) {
    int r = avcodec_send_packet(t->dec, pkt);
    if (r < 0 && r != AVERROR_EOF && r != AVERROR(EAGAIN)) return 0;  // skip a damaged packet
    while ((r = avcodec_receive_frame(t->dec, t->frame)) == 0) {
        if (t->frame->sample_rate <= 0 || t->frame->nb_samples <= 0) { av_frame_unref(t->frame); continue; }
        if (t->frame->format != (int)t->in_fmt || t->frame->sample_rate != t->in_rate ||
            av_channel_layout_compare(&t->frame->ch_layout, &t->in_layout) != 0) {
            if ((r = atx_reconfigure(t, t->frame)) < 0) { av_frame_unref(t->frame); return r; }
        }
        t->frames++;
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
    int discont;                   // this kind of file can have timestamp restarts or jumps (MPEG-TS): smooth them over
    double shift, oldShift;        // seconds taken off every timestamp so far because of such jumps (and before the last one)
    double lastT[2], nextT[2];     // per stream (0 = picture, 1 = sound): last time and expected next time, after smoothing
    int seen[2];
    int jumps;                     // how many jumps were smoothed over
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
    return (t - av_rescale_q(s->start, AV_TIME_BASE_Q, st->time_base)) * av_q2d(st->time_base) - s->shift;
}

static int open_src(Src *s, const char *path, char *err, size_t errlen) {
    int r;
    s->want1 = s->want2 = -1;
    if ((r = open_input_probe(&s->fmt, path)) < 0) { seterr(err, errlen, "Couldn't open the downloaded file", r); return VG_ERROR; }
    if ((r = avformat_find_stream_info(s->fmt, NULL)) < 0) { seterr(err, errlen, "Couldn't read the downloaded file", r); return VG_ERROR; }
    s->start = s->fmt->start_time != AV_NOPTS_VALUE ? s->fmt->start_time : 0;
    s->discont = (s->fmt->iformat->flags & AVFMT_TS_DISCONT) != 0;
    s->peek = av_packet_alloc();
    return VG_OK;
}

static void close_src(Src *s) {
    av_packet_free(&s->peek);
    avformat_close_input(&s->fmt);
}

// ---------------------------------------------------------------- where the picture can start

// Sound with no settings (a declared stream that never carries data) can't be copied or converted: ignore it.
static int usable_audio(const AVStream *st) {
    return st->codecpar->sample_rate > 0 && st->codecpar->ch_layout.nb_channels > 0;
}

// True if an Annex B packet (as MPEG-TS carries H.264/HEVC) contains the codec setup: SPS and PPS (and VPS for HEVC).
static int has_param_sets(enum AVCodecID id, const uint8_t *d, int n) {
    int vps = 0, sps = 0, pps = 0;
    for (int i = 0; i + 3 < n; i++) {
        if (d[i] == 0 && d[i + 1] == 0 && d[i + 2] == 1) {
            if (id == AV_CODEC_ID_HEVC) {
                int t = (d[i + 3] >> 1) & 0x3f;
                if (t == 32) vps = 1; else if (t == 33) sps = 1; else if (t == 34) pps = 1;
            } else {
                int t = d[i + 3] & 0x1f;
                if (t == 7) sps = 1; else if (t == 8) pps = 1;
            }
            i += 2;
        }
    }
    return id == AV_CODEC_ID_HEVC ? (vps && sps && pps) : (sps && pps);
}

// A stream can't be put in an MP4 starting from just anywhere: the first picture has to be a keyframe that has (or
// comes with) its codec setup, or nothing can decode it. This looks through the file for the first such keyframe.
// skip = how many video packets come before it, t0 = its time in seconds from the start of the file.
static int find_start(const char *path, int vi, int *skip, double *t0, char *err, size_t n) {
    Src s;
    memset(&s, 0, sizeof s);
    int r = VG_ERROR;
    AVPacket *pkt = av_packet_alloc();
    if (open_src(&s, path, err, n) != VG_OK) goto end;
    AVStream *vs = s.fmt->streams[vi];
    int haveSetup = vs->codecpar->extradata_size > 0;   // FFmpeg found it while probing (extract_extradata)
    enum AVCodecID id = vs->codecpar->codec_id;
    int64_t startTb = av_rescale_q(s.start, AV_TIME_BASE_Q, vs->time_base);
    int count = 0;
    while (av_read_frame(s.fmt, pkt) >= 0) {
        if (pkt->stream_index == vi) {
            int64_t t = pkt->pts != AV_NOPTS_VALUE ? pkt->pts : pkt->dts;
            if ((pkt->flags & AV_PKT_FLAG_KEY) && !(pkt->flags & AV_PKT_FLAG_CORRUPT) && t != AV_NOPTS_VALUE &&
                (haveSetup || has_param_sets(id, pkt->data, pkt->size))) {
                *skip = count;
                *t0 = (t - startTb) * av_q2d(vs->time_base);
                r = VG_OK;
                av_packet_unref(pkt);
                break;
            }
            count++;
        }
        av_packet_unref(pkt);
    }
    if (r != VG_OK) seterr(err, n, "Couldn't find a place in this video where the picture can start", 0);
end:
    av_packet_free(&pkt);
    if (s.fmt || s.peek) close_src(&s);
    return r;
}

// ---------------------------------------------------------------- video to MP4

static double packet_dur(const AVStream *is, const AVPacket *pkt, int video) {
    if (pkt->duration > 0) return pkt->duration * av_q2d(is->time_base);
    if (video) {
        if (is->avg_frame_rate.num > 0) return 1.0 / av_q2d(is->avg_frame_rate);
        if (is->r_frame_rate.num > 0) return 1.0 / av_q2d(is->r_frame_rate);
        return 1.0 / 30;
    }
    return 1024.0 / (is->codecpar->sample_rate > 0 ? is->codecpar->sample_rate : 48000);
}

// Where this packet sits on the output timeline (seconds, before the start offset), after smoothing over timestamp
// jumps. The rule is the one ffmpeg itself uses for MPEG-TS: a jump of more than 10 s, or time going back by more
// than 0.1 s, moves this packet and every later packet of the same file by the same amount, so that sound and
// picture from one file stay together. Files that can't have such jumps are left exactly as they are.
//
// One more case: after picture from the new part has been read, the demuxer can still hand over the last sound
// packets of the old part. Those must keep the old timing (they would otherwise look like a jump of their own and
// tear a hole in the timeline), so each packet takes whichever of the old and new timing fits its own stream better.
// *usedShift is the shift that applies to this packet.
static double timeline(Src *s, int slot, const AVPacket *pkt, const AVStream *is, double dur, double *usedShift) {
    double tb = av_q2d(is->time_base);
    int64_t startTb = av_rescale_q(s->start, AV_TIME_BASE_Q, is->time_base);
    int hasDts = pkt->dts != AV_NOPTS_VALUE;
    int64_t raw = hasDts ? pkt->dts : pkt->pts;
    double base = (raw - startTb) * tb;
    double t = base - s->shift;
    *usedShift = s->shift;
    if (s->discont) {
        if (s->seen[slot]) {
            double delta = t - s->nextT[slot];
            int jumped = fabs(delta) > 10.0 || (hasDts && t + 0.1 < s->lastT[slot]);
            if (s->oldShift != s->shift && (jumped || fabs(delta) > 0.5)) {
                double told = base - s->oldShift, dold = told - s->nextT[slot];
                if (fabs(dold) < fabs(delta) && fabs(dold) <= 1.0) { t = told; *usedShift = s->oldShift; jumped = 0; }
            }
            if (jumped && *usedShift == s->shift) { s->oldShift = s->shift; s->shift += delta; t -= delta; *usedShift = s->shift; s->jumps++; }
        }
        s->lastT[slot] = t;
        s->nextT[slot] = t + dur;
        s->seen[slot] = 1;
    }
    return t;
}

int vg_mux_mp4_ex(const char *videoIn, const char *audioIn, const char *out, VGMuxInfo *info, vg_progress_cb progress,
                  vg_cancel_cb cancel, void *ctx, char *err, size_t errlen) {
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
    AVCodecParserContext *vparser = NULL;
    AVCodecContext *vpctx = NULL;
    VGMuxInfo local;
    if (!info) info = &local;
    memset(info, 0, sizeof *info);
    long aIn = 0, vSeen = 0;
    int skipV = 0, audioStarted = 0, atxStarted = 0, curW = 0, curH = 0;
    int64_t atxStartPts = 0;
    double sumV = 0;
    double T0 = 0, endV = 0, endA = 0;

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
        if (ai >= 0 && usable_audio(src[1].fmt->streams[ai])) { asrc = &src[1]; src[1].want1 = ai; } else ai = -1;
    } else {
        ai = pick_stream(src[0].fmt, AVMEDIA_TYPE_AUDIO);
        if (ai >= 0 && usable_audio(src[0].fmt->streams[ai])) { asrc = &src[0]; src[0].want2 = ai; } else ai = -1;
    }

    AVStream *ivs = src[0].fmt->streams[vi];
    enum AVCodecID vid = ivs->codecpar->codec_id;
    info->width = ivs->codecpar->width;
    info->height = ivs->codecpar->height;
    info->hadAudio = asrc != NULL;
    if (asrc) snprintf(info->audioIn, sizeof info->audioIn, "%s", avcodec_get_name(asrc->fmt->streams[ai]->codecpar->codec_id));
    if (vid != AV_CODEC_ID_H264 && vid != AV_CODEC_ID_HEVC) {
        char m[96];
        snprintf(m, sizeof m, "VidGrab can't convert %s video yet", avcodec_get_name(vid));
        seterr(err, errlen, m, 0);
        goto end;
    }
    if (ivs->codecpar->width <= 0 || ivs->codecpar->height <= 0) {
        seterr(err, errlen, "Couldn't find the picture size in this video", 0);
        goto end;
    }

    // Where the picture starts: the first keyframe that can be decoded on its own, not simply the first packet.
    if (find_start(videoIn, vi, &skipV, &T0, err, errlen) != VG_OK) goto end;
    info->leadingDropped = skipV;

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
            // Any other sound becomes AAC. If that can't be done the whole conversion fails: no quiet downgrade.
            if (atx_open(&t, ias, ofmt, 0, 192000, err, errlen) != VG_OK) goto end;
            audioTx = 1;
        }
    }
    snprintf(info->strategy, sizeof info->strategy, "video copy (%s), %s%s%s", avcodec_get_name(vid),
             !asrc ? "no audio" : audioCopy ? "audio copy (aac)" : "audio to AAC (from ", asrc && !audioCopy ? info->audioIn : "",
             asrc && !audioCopy ? ")" : "");

    // Picture size can't change part-way: one MP4 track can only hold one size.
    vparser = av_parser_init(vid);
    vpctx = avcodec_alloc_context3(NULL);
    if (vparser && vpctx) {
        avcodec_parameters_to_context(vpctx, ivs->codecpar);
        vparser->flags |= PARSER_FLAG_COMPLETE_FRAMES;
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
        double tb = av_q2d(is->time_base);

        if (isVideo && ++vSeen <= skipV) { av_packet_unref(pkt); continue; }   // before the first usable keyframe

        if (isVideo || (isAudio && audioCopy)) {
            AVStream *os = isVideo ? ovs : oas;
            if (pkt->pts == AV_NOPTS_VALUE && pkt->dts == AV_NOPTS_VALUE) { av_packet_unref(pkt); continue; }
            double shiftUsed = 0;
            double tt = timeline(s, isVideo ? 0 : 1, pkt, is, packet_dur(is, pkt, isVideo), &shiftUsed);
            if (isAudio) {
                // Sound from before the picture starts is dropped, so sound and picture stay lined up.
                if (!audioStarted) { if (tt - T0 < -0.02) { av_packet_unref(pkt); continue; } audioStarted = 1; }
                aIn++;
            } else {
                info->videoIn++;
                sumV += packet_dur(is, pkt, 1);
                if (vparser && vpctx && (pkt->flags & AV_PKT_FLAG_KEY)) {
                    uint8_t *po = NULL;
                    int ps = 0;
                    av_parser_parse2(vparser, vpctx, &po, &ps, pkt->data, pkt->size, pkt->pts, pkt->dts, pkt->pos);
                    if (vparser->width > 0 && vparser->height > 0) {
                        if (!curW) { curW = vparser->width; curH = vparser->height; }
                        else if (vparser->width != curW || vparser->height != curH) {
                            char m[128];
                            snprintf(m, sizeof m, "The picture changes size part-way (%dx%d to %dx%d); one MP4 can't hold that", curW, curH, vparser->width, vparser->height);
                            seterr(err, errlen, m, 0);
                            goto end;
                        }
                    }
                }
            }
            int64_t off = av_rescale_q(s->start, AV_TIME_BASE_Q, is->time_base) + (int64_t)llround((shiftUsed + T0) / tb);
            if (pkt->pts != AV_NOPTS_VALUE) pkt->pts -= off;
            if (pkt->dts != AV_NOPTS_VALUE) pkt->dts -= off;
            {
                int64_t pe = pkt->pts != AV_NOPTS_VALUE ? pkt->pts : pkt->dts;
                double end = pe * tb + packet_dur(is, pkt, isVideo);
                if (isVideo) endV = fmax(endV, end); else endA = fmax(endA, end);
            }
            if (isVideo) {
                if (progress && dur > 0 && pkt->pts != AV_NOPTS_VALUE)
                    progress(ctx, clamp01((pkt->pts * tb + T0) / dur));
                // MKV/WebM only store presentation times (FFmpeg guesses decode times that break
                // B-frames), so always rebuild them there. Other containers keep their own.
                if (synth < 0) synth = (pkt->dts == AV_NOPTS_VALUE || !strncmp(s->fmt->iformat->name, "matroska", 8)) ? 1 : 0;
                if (synth) {
                    if (pkt->pts == AV_NOPTS_VALUE) { av_packet_unref(pkt); continue; }
                    AVPacket *c = av_packet_alloc();
                    av_packet_move_ref(c, pkt);
                    ro.q[ro.qn++] = c;
                    ro.pts[ro.pn++] = c->pts;
                    if (ro.qn > VG_REORDER && reorder_write_front(&ro, ofmt, is, os) < 0) {
                        writeErrors++;
                        info->videoLost++;
                    }
                    if (writeErrors > 300 && writeErrors > (info->videoIn + aIn) / 5) { seterr(err, errlen, "Too many damaged pieces in this video", 0); goto end; }
                    continue;
                }
            }
            if (write_copied(ofmt, pkt, is, os) < 0) {
                writeErrors++;
                if (isVideo) info->videoLost++;
                if (writeErrors > 300 && writeErrors > (info->videoIn + aIn) / 5) { seterr(err, errlen, "Too many damaged pieces in this video", 0); goto end; }
            }
        } else if (isAudio && audioTx) {
            double shiftUsed = 0;
            double ta = timeline(s, 1, pkt, is, packet_dur(is, pkt, 0), &shiftUsed) - T0;
            if (!audioStarted) { if (ta < -0.02) { av_packet_unref(pkt); continue; } audioStarted = 1; }
            // The converted sound is numbered from where it really starts, so a late sound start stays a late sound start.
            if (!atxStarted) { atxStarted = 1; t.next_pts = ta > 0 ? (int64_t)llround(ta * t.enc->sample_rate) : 0; atxStartPts = t.next_pts; }
            aIn++;
            if (aIn >= 300 && t.frames == 0) {
                char m[96];
                snprintf(m, sizeof m, "VidGrab couldn't decode this video's sound (it looks like %s)", info->audioIn);
                seterr(err, errlen, m, 0);
                av_packet_unref(pkt);
                goto end;
            }
            if ((r = atx_packet(&t, ofmt, pkt)) < 0) { seterr(err, errlen, "Audio conversion failed", r); av_packet_unref(pkt); goto end; }
        }
        av_packet_unref(pkt);
    }
    if (!info->videoIn) { seterr(err, errlen, "No picture could be read from this video", 0); goto end; }
    while (ro.qn > 0) {
        if (reorder_write_front(&ro, ofmt, src[0].fmt->streams[vi], ovs) < 0) { writeErrors++; info->videoLost++; }
    }
    if (audioTx) {
        if ((r = atx_packet(&t, ofmt, NULL)) < 0) { seterr(err, errlen, "Audio conversion failed", r); goto end; }
        endA = t.next_pts / (double)t.enc->sample_rate;
        // The sound has to have come out: a mis-detected or damaged track that decodes to (almost) nothing would
        // otherwise leave a silent MP4 that looks fine.
        double got = (t.next_pts - atxStartPts) / (double)t.enc->sample_rate;
        double span = endV - atxStartPts / (double)t.enc->sample_rate;
        if (t.frames == 0 || (span > 3.0 && got < 0.5 * span)) {
            char m[112];
            snprintf(m, sizeof m, "VidGrab couldn't decode most of this video's sound (it looks like %s)", info->audioIn);
            seterr(err, errlen, m, 0);
            goto end;
        }
    }
    if ((r = av_write_trailer(ofmt)) < 0) { seterr(err, errlen, "Couldn't finish the MP4", r); goto end; }
    started = 0;

    info->videoOut = info->videoIn - info->videoLost;
    info->discontinuities = src[0].jumps + src[1].jumps;
    info->expectedDuration = fmax(endV, endA);
    info->gapSeconds = fmax(0, endV - sumV);
    // A few lost pieces are tolerated in damaged input; more than 1 % means the result can't be trusted.
    if (writeErrors > (long)fmax(5, (info->videoIn + aIn) / 100)) {
        char m[96];
        snprintf(m, sizeof m, "Too many damaged pieces in this video (%d lost)", writeErrors);
        seterr(err, errlen, m, 0);
        goto end;
    }
    if (progress) progress(ctx, 1.0);
    ret = VG_OK;

end:
    if (started && ofmt) av_write_trailer(ofmt);
    for (int i = 0; i < ro.qn; i++) av_packet_free(&ro.q[i]);
    if (vparser) av_parser_close(vparser);
    avcodec_free_context(&vpctx);
    atx_free(&t);
    for (int k = 0; k < 2; k++) if (src[k].fmt || src[k].peek) close_src(&src[k]);
    close_output(&ofmt);
    if (ret != VG_OK) remove(out);
    return ret;
}

int vg_mux_mp4(const char *videoIn, const char *audioIn, const char *out, vg_progress_cb progress, vg_cancel_cb cancel,
               void *ctx, char *err, size_t errlen) {
    return vg_mux_mp4_ex(videoIn, audioIn, out, NULL, progress, cancel, ctx, err, errlen);
}

int vg_remux_mp4(const char *in, const char *out, vg_progress_cb progress, vg_cancel_cb cancel, void *ctx,
                 char *err, size_t errlen) {
    return vg_mux_mp4_ex(in, NULL, out, NULL, progress, cancel, ctx, err, errlen);
}

// ---------------------------------------------------------------- checking the result

int vg_validate_mp4(const char *path, double expectDur, int wantAudio, char *summary, size_t sumlen, char *err, size_t errlen) {
    AVFormatContext *f = NULL;
    AVCodecContext *dc = NULL;
    AVPacket *pkt = av_packet_alloc();
    AVFrame *fr = av_frame_alloc();
    int ret = VG_ERROR, r;
    if (summary && sumlen) summary[0] = 0;
    if ((r = avformat_open_input(&f, path, NULL, NULL)) < 0) { seterr(err, errlen, "The converted file can't be opened", r); goto end; }
    if ((r = avformat_find_stream_info(f, NULL)) < 0) { seterr(err, errlen, "The converted file can't be read", r); goto end; }
    int v = pick_stream(f, AVMEDIA_TYPE_VIDEO), a = pick_stream(f, AVMEDIA_TYPE_AUDIO);
    if (v < 0) { seterr(err, errlen, "The converted file has no video", 0); goto end; }
    AVCodecParameters *cp = f->streams[v]->codecpar;
    if (cp->codec_id != AV_CODEC_ID_H264 && cp->codec_id != AV_CODEC_ID_HEVC) { seterr(err, errlen, "The converted video isn't H.264 or HEVC", 0); goto end; }
    if (cp->codec_id == AV_CODEC_ID_HEVC && cp->codec_tag != MKTAG('h', 'v', 'c', '1')) { seterr(err, errlen, "The converted HEVC video isn't tagged the way iPhone needs", 0); goto end; }
    if (cp->width <= 0 || cp->height <= 0) { seterr(err, errlen, "The converted video has no picture size", 0); goto end; }
    if (cp->extradata_size < 7) { seterr(err, errlen, "The converted video is missing its codec setup", 0); goto end; }
    if (wantAudio && a < 0) { seterr(err, errlen, "The converted file lost its sound", 0); goto end; }
    if (a >= 0 && f->streams[a]->codecpar->codec_id != AV_CODEC_ID_AAC) { seterr(err, errlen, "The converted sound isn't AAC", 0); goto end; }
    double dur = f->duration > 0 ? f->duration / (double)AV_TIME_BASE : 0;
    if (dur <= 0) { seterr(err, errlen, "The converted file has no length", 0); goto end; }
    if (expectDur > 0 && fabs(dur - expectDur) > fmax(1.0, expectDur * 0.03)) {
        char m[96];
        snprintf(m, sizeof m, "The converted file is the wrong length (%.1f s instead of %.1f s)", dur, expectDur);
        seterr(err, errlen, m, 0);
        goto end;
    }

    const AVCodec *dec = avcodec_find_decoder(cp->codec_id);
    dc = dec ? avcodec_alloc_context3(dec) : NULL;
    if (!dc || avcodec_parameters_to_context(dc, cp) < 0 || avcodec_open2(dc, dec, NULL) < 0) { seterr(err, errlen, "Couldn't open a decoder to check the video", 0); goto end; }
    for (int pass = 0; pass < 2; pass++) {
        if (pass == 1) {
            if (dur < 4) break;
            if (av_seek_frame(f, v, av_rescale_q((int64_t)(dur * 0.5 * AV_TIME_BASE), AV_TIME_BASE_Q, f->streams[v]->time_base), AVSEEK_FLAG_BACKWARD) < 0) break;
            avcodec_flush_buffers(dc);
        }
        int got = 0, first = 1;
        for (int n = 0; n < 150 && !got && av_read_frame(f, pkt) >= 0; ) {
            if (pkt->stream_index == v) {
                n++;
                if (first && !(pkt->flags & AV_PKT_FLAG_KEY)) {
                    seterr(err, errlen, pass ? "The converted video can't be played from the middle" : "The converted video doesn't start on a keyframe", 0);
                    av_packet_unref(pkt);
                    goto end;
                }
                first = 0;
                if (avcodec_send_packet(dc, pkt) >= 0 && avcodec_receive_frame(dc, fr) >= 0) got = 1;
            }
            av_packet_unref(pkt);
        }
        if (!got) { seterr(err, errlen, pass ? "No picture could be read from the middle of the converted video" : "No picture could be read at the start of the converted video", 0); goto end; }
    }
    if (a >= 0) {
        AVCodecContext *ac = NULL;
        const AVCodec *adec = avcodec_find_decoder(f->streams[a]->codecpar->codec_id);
        ac = adec ? avcodec_alloc_context3(adec) : NULL;
        int agot = 0;
        if (ac && avcodec_parameters_to_context(ac, f->streams[a]->codecpar) >= 0 && avcodec_open2(ac, adec, NULL) >= 0 &&
            av_seek_frame(f, a, 0, AVSEEK_FLAG_BACKWARD) >= 0) {
            for (int n = 0; n < 60 && !agot && av_read_frame(f, pkt) >= 0; ) {
                if (pkt->stream_index == a) { n++; if (avcodec_send_packet(ac, pkt) >= 0 && avcodec_receive_frame(ac, fr) >= 0) agot = 1; }
                av_packet_unref(pkt);
            }
        }
        avcodec_free_context(&ac);
        if (!agot) { seterr(err, errlen, "The converted sound can't be decoded", 0); goto end; }
    }
    if (summary && sumlen)
        snprintf(summary, sumlen, "%s %dx%d, %s%s, %.1f s (expected %.1f s)", avcodec_get_name(cp->codec_id), cp->width, cp->height,
                 a >= 0 ? "aac " : "no audio", a >= 0 ? (f->streams[a]->codecpar->ch_layout.nb_channels > 1 ? "stereo" : "mono") : "", dur, expectDur);
    ret = VG_OK;
end:
    avcodec_free_context(&dc);
    av_frame_free(&fr);
    av_packet_free(&pkt);
    avformat_close_input(&f);
    return ret;
}

// ---- MPEG-TS cleaner -------------------------------------------------------------------------------------------
// Some sites glue a fake picture header (a tiny PNG/GIF/JPEG) in front of every piece of a stream, to hide it from
// download tools. Players that are forgiving cope; FFmpeg and VLC lose track of the streams. This copies only the real
// 188-byte packets and drops everything between them. It never touches the video or the sound itself.

// True when buf[i] starts a run of packets (0x47 every 188 bytes). Near the end of the data fewer are accepted.
static int ts_run_at(const unsigned char *b, size_t len, size_t i, int need) {
    int ok = 0;
    if (i + 188 > len) return 0; // not even one whole packet
    for (int k = 0; k < need; k++) {
        size_t p = i + (size_t)k * 188;
        if (p >= len) break;
        if (b[p] != 0x47) return 0;
        ok++;
    }
    return ok > 0;
}

// Runs over `limit` bytes of the file (0 = all). Writes the clean packets to `out` when it is not NULL.
static int ts_clean_pass(FILE *in, FILE *out, long long limit, long long *junk, long *pieces,
                         vg_progress_cb progress, vg_cancel_cb cancel, void *ctx, long long total) {
    enum { CH = 8 * 1024 * 1024, RUN = 5 };
    unsigned char *b = malloc(CH);
    if (!b) return VG_ERROR;
    size_t len = 0, p = 0;
    long long done = 0;
    int eof = 0, synced = 0, rc = VG_OK;
    *junk = 0; *pieces = 0;
    while (1) {
        if (cancel && cancel(ctx)) { rc = VG_CANCELLED; break; }
        if (len - p < (size_t)(RUN + 1) * 188 && !eof) {
            memmove(b, b + p, len - p);
            len -= p; p = 0;
            size_t got = fread(b + len, 1, CH - len, in);
            if (got == 0) eof = 1;
            len += got;
            continue;
        }
        if (p >= len) break;
        if (limit && done >= limit) break;
        if (len - p >= 188 && b[p] == 0x47 && (synced || ts_run_at(b, len, p, RUN))) {
            // a good packet; check the next one is also good, otherwise this was a false start
            if (out && fwrite(b + p, 1, 188, out) != 188) { rc = VG_ERROR; break; }
            p += 188; done += 188;
            if (!synced) { synced = 1; (*pieces)++; }
            if (progress && total > 0 && (done & 0xFFFFF) < 188) progress(ctx, (double)done / (double)total);
            continue;
        }
        // lost sync (or never had it): skip ahead to the next place where a run of packets starts
        synced = 0;
        size_t q = p;
        int found = 0;
        while (q < len) {
            if (b[q] == 0x47 && (eof || len - q >= (size_t)RUN * 188) && ts_run_at(b, len, q, RUN)) { found = 1; break; }
            if (!eof && len - q < (size_t)RUN * 188) break; // need more data to decide
            q++;
        }
        *junk += (long long)(q - p);
        done += (long long)(q - p);
        p = q;
        if (found) continue;
        if (eof) { *junk += (long long)(len - p); break; } // what is left is not a packet
    }
    free(b);
    return rc;
}

int vg_ts_clean(const char *in, const char *out, long long *junkBytes, long *pieces, int *needed,
                vg_progress_cb progress, vg_cancel_cb cancel, void *ctx, char *err, size_t errlen) {
    if (junkBytes) *junkBytes = 0;
    if (pieces) *pieces = 0;
    if (needed) *needed = 0;
    FILE *f = fopen(in, "rb");
    if (!f) { seterr(err, errlen, "can't open the file to check it", 0); return VG_ERROR; }
    unsigned char head[12];
    size_t hn = fread(head, 1, sizeof head, f);
    if (hn < sizeof head) { fclose(f); return VG_OK; }
    // Whole-file formats that can't be a glued transport stream: leave them alone (and skip the scan).
    if (!memcmp(head + 4, "ftyp", 4) || !memcmp(head, "\x1a\x45\xdf\xa3", 4) || !memcmp(head, "FLV", 3) || !memcmp(head, "#EXTM3U", 7)) {
        fclose(f); return VG_OK;
    }
    fseek(f, 0, SEEK_END);
    long long total = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (total < 188 * 8) { fclose(f); return VG_OK; }

    // 1. quick look at the start: is it a transport stream with junk in it?
    long long j = 0; long pc = 0;
    int rc = ts_clean_pass(f, NULL, 48LL * 1024 * 1024, &j, &pc, NULL, cancel, ctx, total);
    if (rc != VG_OK) { fclose(f); return rc; }
    // Nothing to do when it is clean, and nothing we can do when there are no packets at all (not a TS file).
    if (j == 0 || pc == 0) { fclose(f); return VG_OK; }
    // A file that is mostly junk is not a stream we understand
    if (j > total / 2) { fclose(f); return VG_OK; }
    if (needed) *needed = 1;
    if (!out) { fclose(f); return VG_OK; }

    // 2. write the clean copy
    FILE *o = fopen(out, "wb");
    if (!o) { fclose(f); seterr(err, errlen, "can't write the cleaned copy", 0); return VG_ERROR; }
    fseek(f, 0, SEEK_SET);
    rc = ts_clean_pass(f, o, 0, &j, &pc, progress, cancel, ctx, total);
    int werr = fclose(o);
    fclose(f);
    if (rc != VG_OK || werr != 0) {
        remove(out);
        if (rc == VG_OK) { seterr(err, errlen, "couldn't save the cleaned copy", 0); rc = VG_ERROR; }
        return rc;
    }
    if (junkBytes) *junkBytes = j;
    if (pieces) *pieces = pc;
    return VG_OK;
}
