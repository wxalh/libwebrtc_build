#include <cstdio>

#include "rtc_base/ssl_adapter.h"

#ifndef WEBRTC_SMOKE_SSL_NAMESPACE
#define WEBRTC_SMOKE_SSL_NAMESPACE rtc
#endif

int main() {
  if (!WEBRTC_SMOKE_SSL_NAMESPACE::InitializeSSL()) {
    std::fprintf(stderr, "webrtc_smoke_test: InitializeSSL failed\n");
    return 2;
  }
  WEBRTC_SMOKE_SSL_NAMESPACE::CleanupSSL();
  std::printf("webrtc_smoke_test: ok\n");
  return 0;
}
