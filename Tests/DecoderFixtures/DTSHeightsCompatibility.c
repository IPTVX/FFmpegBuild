// Decode an official FATE DTS/DTS-HD sample through the shipped public APIs.
// A sample without DTS:X heights must produce identical PCM with x_heights on/off.
#include <AetherLibavcodec/avcodec.h>
#include <AetherLibavformat/avformat.h>
#include <AetherLibavutil/opt.h>
#include <AetherLibavutil/md5.h>
#include <AetherLibavutil/mem.h>
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>

static void decode(const char *path, int heights, uint8_t digest[16]) {
    AVFormatContext *format = NULL;
    assert(avformat_open_input(&format, path, NULL, NULL) >= 0);
    assert(avformat_find_stream_info(format, NULL) >= 0);
    const AVCodec *codec = NULL;
    int stream = av_find_best_stream(format, AVMEDIA_TYPE_AUDIO, -1, -1, &codec, 0);
    assert(stream >= 0 && codec->id == AV_CODEC_ID_DTS);
    AVCodecContext *context = avcodec_alloc_context3(codec);
    assert(context && avcodec_parameters_to_context(context, format->streams[stream]->codecpar) >= 0);
    assert(av_opt_set_int(context->priv_data, "x_heights", heights, 0) >= 0);
    assert(avcodec_open2(context, codec, NULL) >= 0);
    AVPacket *packet = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    struct AVMD5 *hash = av_md5_alloc();
    av_md5_init(hash);
    int frames = 0;
    int64_t samples = 0;
    while (av_read_frame(format, packet) >= 0) {
        if (packet->stream_index == stream) {
            assert(avcodec_send_packet(context, packet) >= 0);
            while (avcodec_receive_frame(context, frame) >= 0) {
                int planar = av_sample_fmt_is_planar(frame->format);
                int channels = frame->ch_layout.nb_channels;
                int length = frame->nb_samples * av_get_bytes_per_sample(frame->format);
                av_md5_update(hash, (uint8_t *)&channels, sizeof(channels));
                av_md5_update(hash, (uint8_t *)&frame->nb_samples, sizeof(frame->nb_samples));
                for (int i = 0; i < (planar ? channels : 1); ++i)
                    av_md5_update(hash, frame->extended_data[i], length * (planar ? 1 : channels));
                frames++;
                samples += frame->nb_samples;
                av_frame_unref(frame);
            }
        }
        av_packet_unref(packet);
    }
    assert(frames > 0 && samples > 0);
    int64_t presentation = -1;
    int has_presentation = av_opt_get_int(context->priv_data, "x_presentation", 0, &presentation) >= 0;
    assert(!has_presentation || presentation == 0);
    av_md5_final(hash, digest);
    printf("x_heights=%d frames=%d samples=%" PRId64 " x_presentation=%" PRId64 " PCM=", heights, frames, samples, presentation);
    for (int i = 0; i < 16; ++i) printf("%02x", digest[i]);
    puts("");
    av_free(hash);
    av_frame_free(&frame);
    av_packet_free(&packet);
    avcodec_free_context(&context);
    avformat_close_input(&format);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    uint8_t disabled[16], enabled[16];
    decode(argv[1], 0, disabled);
    decode(argv[1], 1, enabled);
    assert(memcmp(disabled, enabled, sizeof(disabled)) == 0);
    puts("PASS unchanged DTS-HD PCM with optional heights enabled");
}
