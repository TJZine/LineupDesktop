/* Synthetic two-line bitmap input for FFmpeg's dvdsub encoder.
 * Text rasterization is fixture-only FreeType, independent of product rendering.
 */
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/mem.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define WIDTH 320
#define HEIGHT 70

static int draw_line(FT_Face face, uint8_t *pixels, const char *text, int baseline) {
    int advance = 0;
    for (const char *p = text; *p; ++p) {
        if (FT_Load_Char(face, *p, FT_LOAD_RENDER)) return -1;
        advance += face->glyph->advance.x >> 6;
    }
    int pen = (WIDTH - advance) / 2;
    for (const char *p = text; *p; ++p) {
        if (FT_Load_Char(face, *p, FT_LOAD_RENDER)) return -1;
        FT_GlyphSlot glyph = face->glyph;
        for (unsigned y = 0; y < glyph->bitmap.rows; ++y) {
            for (unsigned x = 0; x < glyph->bitmap.width; ++x) {
                int px = pen + glyph->bitmap_left + x;
                int py = baseline - glyph->bitmap_top + y;
                if (px >= 0 && px < WIDTH && py >= 0 && py < HEIGHT &&
                    glyph->bitmap.buffer[y * glyph->bitmap.pitch + x] >= 96)
                    pixels[py * WIDTH + px] = 1;
            }
        }
        pen += glyph->advance.x >> 6;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 3) return 1; /* font, output MKV */
    int status = 1;
    FT_Library ft = NULL;
    FT_Face face = NULL;
    AVCodecContext *codec = NULL;
    AVFormatContext *format = NULL;
    AVPacket *packet = NULL;
    uint8_t pixels[WIDTH * HEIGHT] = {0};
    uint8_t outlined[WIDTH * HEIGHT] = {0};
    uint32_t palette[4] = {0, 0xffffffff, 0xff000000, 0};
    if (FT_Init_FreeType(&ft) || FT_New_Face(ft, argv[1], 0, &face) ||
        FT_Set_Pixel_Sizes(face, 0, 24) || draw_line(face, pixels, "Look out!", 27) ||
        draw_line(face, pixels, "[Door creaks]", 59)) goto cleanup;
    for (int y = 0; y < HEIGHT; ++y) {
        for (int x = 0; x < WIDTH; ++x) {
            if (!pixels[y * WIDTH + x]) continue;
            for (int dy = -2; dy <= 2; ++dy)
                for (int dx = -2; dx <= 2; ++dx)
                    if (x + dx >= 0 && x + dx < WIDTH && y + dy >= 0 && y + dy < HEIGHT)
                        outlined[(y + dy) * WIDTH + x + dx] = 2;
        }
    }
    for (int i = 0; i < WIDTH * HEIGHT; ++i) if (pixels[i]) outlined[i] = 1;
    codec = avcodec_alloc_context3(avcodec_find_encoder(AV_CODEC_ID_DVD_SUBTITLE));
    if (!codec) goto cleanup;
    codec->width = 640;
    codec->height = 360;
    codec->time_base = (AVRational){1, 1000};
    if (avcodec_open2(codec, codec->codec, NULL) < 0 ||
        avformat_alloc_output_context2(&format, NULL, "matroska", argv[2]) < 0) goto cleanup;
    AVStream *stream = avformat_new_stream(format, NULL);
    if (!stream || avcodec_parameters_from_context(stream->codecpar, codec) < 0) goto cleanup;
    stream->time_base = codec->time_base;
    if (avio_open(&format->pb, argv[2], AVIO_FLAG_WRITE) < 0 || avformat_write_header(format, NULL) < 0) goto cleanup;
    AVSubtitleRect rect = {0};
    rect.type = SUBTITLE_BITMAP;
    rect.x = 160; rect.y = 270; rect.w = WIDTH; rect.h = HEIGHT;
    rect.nb_colors = 4; rect.linesize[0] = WIDTH;
    rect.data[0] = outlined; rect.data[1] = (uint8_t *)palette;
    AVSubtitleRect *rects[] = {&rect};
    AVSubtitle subtitle = {0};
    subtitle.num_rects = 1; subtitle.rects = rects; subtitle.end_display_time = 28500;
    uint8_t buffer[65536];
    int size = avcodec_encode_subtitle(codec, buffer, sizeof(buffer), &subtitle);
    if (size < 0) goto cleanup;
    packet = av_packet_alloc();
    if (!packet || av_new_packet(packet, size) < 0) goto cleanup;
    memcpy(packet->data, buffer, size);
    packet->pts = packet->dts = 500;
    packet->duration = 28500;
    packet->stream_index = stream->index;
    if (av_interleaved_write_frame(format, packet) < 0 || av_write_trailer(format) < 0) goto cleanup;
    status = 0;
cleanup:
    av_packet_free(&packet);
    if (format) { avio_closep(&format->pb); avformat_free_context(format); }
    avcodec_free_context(&codec);
    if (face) FT_Done_Face(face);
    if (ft) FT_Done_FreeType(ft);
    if (status) fprintf(stderr, "Synthetic bitmap subtitle generation failed\n");
    return status;
}
