#ifndef PROTOCOL_M4V1_H
#define PROTOCOL_M4V1_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define M4V1_MAGIC             0x4D345631U /* "M4V1" */
#define M4V1_PROTOCOL_VERSION  1U
#define M4V1_HEADER_SIZE       64U

/* Message Types */
#define M4V1_MSG_JOB_BEGIN     1U
#define M4V1_MSG_FRAME_BEGIN   2U
#define M4V1_MSG_FRAME_DATA    3U
#define M4V1_MSG_FRAME_END     4U
#define M4V1_MSG_JOB_END       5U
#define M4V1_MSG_ACK           6U
#define M4V1_MSG_ERROR         7U
#define M4V1_MSG_OUTPUT_DATA   8U
#define M4V1_MSG_OUTPUT_END    9U

/* Output Profiles */
#define M4V1_PROFILE_144P      1U  /* 256x144 visible */
#define M4V1_PROFILE_240P      2U  /* 426x240 visible */

/* Scaler Filters */
#define M4V1_FILTER_BILINEAR   1U  /* Fixed-point separable bilinear */

/* Aspect Policies */
#define M4V1_ASPECT_CENTERED   1U  /* Preserve aspect with centered bars */

/* Color Ranges */
#define M4V1_COLOR_LIMITED     1U  /* Limited/TV range: Y 16..235, UV 16..240 */
#define M4V1_COLOR_FULL        2U  /* Full/PC range: Y 0..255, UV 0..255 */

#define M4V1_PIXEL_FORMAT_I420 1U

/* Wire Header (64 bytes, big-endian) */
#pragma pack(push, 1)
typedef struct {
    uint8_t  magic[4];           /* 0..3: "M4V1" */
    uint16_t protocol_version;   /* 4..5: 1 */
    uint16_t message_type;       /* 6..7: MSG_* */
    uint32_t sequence_number;    /* 8..11 */
    uint32_t frame_id;           /* 12..15 */
    uint32_t width;              /* 16..19: Source width */
    uint32_t height;             /* 20..23: Source height */
    uint16_t pixel_format;       /* 24..25: I420 = 1 */
    uint16_t flags;              /* 26..27 */
    uint64_t pts;                /* 28..35: Presentation timestamp */
    uint32_t duration;           /* 36..39: Frame duration */
    uint32_t payload_length;     /* 40..43: Bytes following header */
    uint32_t frame_total_bytes;  /* 44..47: Expected total frame bytes */
    uint32_t payload_crc32;      /* 48..51: CRC of payload */
    uint32_t frame_crc32;        /* 52..55: Whole-frame CRC */
    uint32_t timebase_num;       /* 56..59: Timescale numerator */
    uint32_t timebase_den;       /* 60..63: Timescale denominator */
} m4v1_header_t;

/* JOB_BEGIN Payload (16 bytes, big-endian) */
typedef struct {
    uint32_t output_profile_id;    /* 1=144p, 2=240p */
    uint32_t scaler_filter_id;     /* 1=bilinear */
    uint32_t aspect_policy_id;     /* 1=centered bars */
    uint32_t input_color_range_id; /* 1=limited, 2=full */
} m4v1_job_begin_payload_t;

/* JOB_BEGIN ACK Payload (12 bytes, big-endian) */
typedef struct {
    uint32_t output_profile_id;
    uint32_t output_width;
    uint32_t output_height;
} m4v1_job_begin_ack_payload_t;
#pragma pack(pop)

static inline int m4v1_derive_output_dims(uint32_t profile_id, uint32_t *out_w, uint32_t *out_h) {
    if (profile_id == M4V1_PROFILE_144P) {
        if (out_w) *out_w = 256U;
        if (out_h) *out_h = 144U;
        return 0;
    } else if (profile_id == M4V1_PROFILE_240P) {
        if (out_w) *out_w = 426U;
        if (out_h) *out_h = 240U;
        return 0;
    }
    return -1;
}

#ifdef __cplusplus
}
#endif

#endif /* PROTOCOL_M4V1_H */
