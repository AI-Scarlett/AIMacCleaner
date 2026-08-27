#include "NetworkTrafficPcapBridge.h"

#include <pcap/pcap.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void tf_copy_error(char *destination, size_t capacity, const char *message) {
    if (destination == NULL || capacity == 0) {
        return;
    }

    snprintf(destination, capacity, "%s", message == NULL ? "Unknown libpcap error" : message);
}

static void tf_append_device_line(
    char *buffer,
    size_t capacity,
    const char *name,
    const char *description,
    uint32_t flags
) {
    size_t used = strlen(buffer);
    if (used >= capacity) {
        return;
    }

    const char *safe_name = name == NULL ? "" : name;
    const char *safe_description = description == NULL ? "" : description;
    snprintf(
        buffer + used,
        capacity - used,
        "%s\t%u\t%s\n",
        safe_name,
        flags,
        safe_description
    );
}

int32_t tf_pcap_list_devices(char *buffer, size_t capacity, char *error_buffer, size_t error_capacity) {
    if (buffer == NULL || capacity == 0) {
        tf_copy_error(error_buffer, error_capacity, "Device output buffer is missing");
        return -1;
    }

    buffer[0] = '\0';
    char pcap_error[PCAP_ERRBUF_SIZE] = {0};
    pcap_if_t *devices = NULL;
    if (pcap_findalldevs(&devices, pcap_error) != 0) {
        tf_copy_error(error_buffer, error_capacity, pcap_error);
        return -1;
    }

    int32_t count = 0;
    for (pcap_if_t *device = devices; device != NULL; device = device->next) {
        tf_append_device_line(buffer, capacity, device->name, device->description, device->flags);
        count += 1;
    }
    pcap_freealldevs(devices);
    return count;
}

static int32_t tf_apply_filter(
    pcap_t *handle,
    const char *filter,
    char *error_buffer,
    size_t error_capacity
) {
    if (filter == NULL || filter[0] == '\0') {
        return 0;
    }

    struct bpf_program program;
    if (pcap_compile(handle, &program, filter, 1, PCAP_NETMASK_UNKNOWN) != 0) {
        tf_copy_error(error_buffer, error_capacity, pcap_geterr(handle));
        return -1;
    }

    int32_t status = pcap_setfilter(handle, &program);
    pcap_freecode(&program);
    if (status != 0) {
        tf_copy_error(error_buffer, error_capacity, pcap_geterr(handle));
        return -1;
    }

    return 0;
}

TFPcapHandle tf_pcap_open_live(
    const char *device,
    const char *filter,
    int32_t snap_length,
    int32_t timeout_milliseconds,
    char *error_buffer,
    size_t error_capacity
) {
    if (device == NULL || device[0] == '\0') {
        tf_copy_error(error_buffer, error_capacity, "A capture interface is required");
        return NULL;
    }

    char pcap_error[PCAP_ERRBUF_SIZE] = {0};
    pcap_t *handle = pcap_open_live(
        device,
        snap_length > 0 ? snap_length : 65535,
        0,
        timeout_milliseconds > 0 ? timeout_milliseconds : 250,
        pcap_error
    );
    if (handle == NULL) {
        tf_copy_error(error_buffer, error_capacity, pcap_error);
        return NULL;
    }

    if (tf_apply_filter(handle, filter, error_buffer, error_capacity) != 0) {
        pcap_close(handle);
        return NULL;
    }

    return handle;
}

TFPcapHandle tf_pcap_open_offline(const char *path, char *error_buffer, size_t error_capacity) {
    if (path == NULL || path[0] == '\0') {
        tf_copy_error(error_buffer, error_capacity, "A PCAP file path is required");
        return NULL;
    }

    char pcap_error[PCAP_ERRBUF_SIZE] = {0};
    pcap_t *handle = pcap_open_offline(path, pcap_error);
    if (handle == NULL) {
        tf_copy_error(error_buffer, error_capacity, pcap_error);
        return NULL;
    }
    return handle;
}

int32_t tf_pcap_next_packet(
    TFPcapHandle opaque_handle,
    uint8_t *packet_buffer,
    uint32_t packet_capacity,
    uint32_t *captured_length,
    uint32_t *original_length,
    int64_t *timestamp_seconds,
    int32_t *timestamp_microseconds,
    char *error_buffer,
    size_t error_capacity
) {
    pcap_t *handle = (pcap_t *)opaque_handle;
    if (handle == NULL || packet_buffer == NULL || packet_capacity == 0) {
        tf_copy_error(error_buffer, error_capacity, "Capture handle or packet buffer is missing");
        return -1;
    }

    struct pcap_pkthdr *header = NULL;
    const u_char *packet = NULL;
    int32_t status = pcap_next_ex(handle, &header, &packet);
    if (status <= 0) {
        if (status == -1) {
            tf_copy_error(error_buffer, error_capacity, pcap_geterr(handle));
        }
        return status;
    }

    uint32_t copy_length = header->caplen < packet_capacity ? header->caplen : packet_capacity;
    memcpy(packet_buffer, packet, copy_length);
    if (captured_length != NULL) {
        *captured_length = copy_length;
    }
    if (original_length != NULL) {
        *original_length = header->len;
    }
    if (timestamp_seconds != NULL) {
        *timestamp_seconds = (int64_t)header->ts.tv_sec;
    }
    if (timestamp_microseconds != NULL) {
        *timestamp_microseconds = (int32_t)header->ts.tv_usec;
    }
    return 1;
}

int32_t tf_pcap_datalink(TFPcapHandle opaque_handle) {
    pcap_t *handle = (pcap_t *)opaque_handle;
    return handle == NULL ? -1 : pcap_datalink(handle);
}

void tf_pcap_break_loop(TFPcapHandle opaque_handle) {
    pcap_t *handle = (pcap_t *)opaque_handle;
    if (handle != NULL) {
        pcap_breakloop(handle);
    }
}

void tf_pcap_close(TFPcapHandle opaque_handle) {
    pcap_t *handle = (pcap_t *)opaque_handle;
    if (handle != NULL) {
        pcap_close(handle);
    }
}
