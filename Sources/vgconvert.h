// VidGrab converter core (plain C on top of FFmpeg).
// Repackages H.264/HEVC videos into MP4 and converts audio to AAC (M4A) or MP3.
#ifndef VGCONVERT_H
#define VGCONVERT_H

#include <stddef.h>

typedef int (*vg_cancel_cb)(void *ctx);
typedef void (*vg_progress_cb)(void *ctx, double fraction);

typedef struct {
    char video[32];      // codec name, "" if none (e.g. "h264", "hevc", "vp9")
    char audio[32];      // codec name, "" if none (e.g. "aac", "opus")
    char container[64];  // e.g. "mpegts", "matroska,webm", "mov,mp4,m4a,3gp,3g2,mj2"
    double duration;     // seconds, 0 if unknown
} VGProbe;

enum { VG_OK = 0, VG_ERROR = -1, VG_CANCELLED = -2 };

int vg_probe(const char *path, VGProbe *out);

/// Writes one line per stream in the file (type, codec, size) for diagnostics.
int vg_describe(const char *path, char *buf, size_t n);

/// Copies H.264/HEVC video into an MP4 (no quality loss). Audio is copied if AAC,
/// otherwise converted to AAC. Fails if the video codec can't go in MP4 as-is.
int vg_remux_mp4(const char *in, const char *out,
                 vg_progress_cb progress, vg_cancel_cb cancel, void *ctx,
                 char *err, size_t errlen);

/// Like vg_remux_mp4, but takes the video from videoIn and the sound from audioIn
/// (e.g. YouTube's separate video and audio downloads). audioIn may be NULL.
int vg_mux_mp4(const char *videoIn, const char *audioIn, const char *out,
               vg_progress_cb progress, vg_cancel_cb cancel, void *ctx,
               char *err, size_t errlen);

/// Converts the first audio stream to AAC in an .m4a (mp3 = 0) or to MP3 (mp3 = 1).
int vg_audio(const char *in, const char *out, int mp3, int bitrate,
             const char *title, const char *artist,
             vg_progress_cb progress, vg_cancel_cb cancel, void *ctx,
             char *err, size_t errlen);

#endif
