#ifndef NETWORK_TRAFFIC_PCAP_BRIDGE_H
#define NETWORK_TRAFFIC_PCAP_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *TFPcapHandle;

int32_t tf_pcap_list_devices(char *buffer, size_t capacity, char *error_buffer, size_t error_capacity);

TFPcapHandle tf_pcap_open_live(
    const char *device,
    const char *filter,
    int32_t snap_length,
    int32_t timeout_milliseconds,
    char *error_buffer,
    size_t error_capacity
);

TFPcapHandle tf_pcap_open_offline(
    const char *path,
    char *error_buffer,
    size_t error_capacity
);

int32_t tf_pcap_next_packet(
    TFPcapHandle handle,
    uint8_t *packet_buffer,
    uint32_t packet_capacity,
    uint32_t *captured_length,
    uint32_t *original_length,
    int64_t *timestamp_seconds,
    int32_t *timestamp_microseconds,
    char *error_buffer,
    size_t error_capacity
);

int32_t tf_pcap_datalink(TFPcapHandle handle);
void tf_pcap_break_loop(TFPcapHandle handle);
void tf_pcap_close(TFPcapHandle handle);

#ifdef __cplusplus
}
#endif

#endif
