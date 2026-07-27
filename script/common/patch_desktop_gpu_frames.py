#!/usr/bin/env python3
import sys
from pathlib import Path


def read(path):
    return path.read_text(encoding="utf-8", errors="strict")


def write_if_changed(path, text):
    old = read(path)
    if old != text:
        path.write_text(text, encoding="utf-8", newline="")
        print(f"Patched {path}")


def replace_once(text, old, new, what):
    if old not in text:
        raise RuntimeError(f"Could not patch {what}: anchor not found")
    return text.replace(old, new, 1)


def replace_if_present(text, old, new):
    return text.replace(old, new, 1) if old in text else text


def ensure_include(text, include):
    if include in text:
        return text
    marker = "#include "
    pos = text.find(marker)
    if pos == -1:
        return include + "\n" + text
    end = text.find("\n\n", pos)
    if end == -1:
        return include + "\n" + text
    return text[:end] + "\n" + include + text[end:]


def patch_desktop_frame(root):
    header = root / "modules/desktop_capture/desktop_frame.h"
    cc = root / "modules/desktop_capture/desktop_frame.cc"
    if not header.exists() or not cc.exists():
        return

    text = read(header)
    if "DesktopFrameGpuData" not in text:
        text = replace_once(
            text,
            "const float kStandardDPI = 96.0f;\n\n// DesktopFrame represents",
            """const float kStandardDPI = 96.0f;

// Optional platform-native GPU surface attached to a DesktopFrame. CPU BGRA
// data remains available through DesktopFrame::data() for compatibility.
struct RTC_EXPORT DesktopFrameGpuData {
  enum class Type {
    kD3D11Texture2D,
    kDmaBuf,
  };

  struct DmaBufPlane {
    int fd = -1;
    uint32_t stride = 0;
    uint32_t offset = 0;
  };

  Type type;
  DesktopSize size;
  DesktopVector offset;
  uint32_t format = 0;
  uint64_t modifier = 0;
  void* texture = nullptr;
  void* device = nullptr;
  uint32_t subresource_index = 0;
  std::vector<DmaBufPlane> dma_buf_planes;

  // Keeps platform resources alive while this descriptor is reachable. Windows
  // uses COM references; Linux duplicates DMA-BUF fds and closes them here.
  std::shared_ptr<void> lifetime;
};

// DesktopFrame represents""",
            "DesktopFrameGpuData declaration",
        )
        anchor = "  // Data buffer used for the frame.\n  uint8_t* data() const { return data_; }\n"
        text = replace_once(
            text,
            anchor,
            anchor
            + """
  // Optional raw GPU surface for applications that want to choose their own
  // zero-copy, GPU-copy, or CPU fallback encoding path.
  const std::shared_ptr<DesktopFrameGpuData>& gpu_data() const {
    return gpu_data_;
  }
  void set_gpu_data(std::shared_ptr<DesktopFrameGpuData> gpu_data) {
    gpu_data_ = gpu_data;
  }
  void clear_gpu_data() { gpu_data_.reset(); }
""",
            "DesktopFrame gpu_data accessors",
        )
        text = replace_once(
            text,
            "  std::vector<uint8_t> icc_profile_;\n",
            "  std::vector<uint8_t> icc_profile_;\n  std::shared_ptr<DesktopFrameGpuData> gpu_data_;\n",
            "DesktopFrame gpu_data member",
        )
        write_if_changed(header, text)



def patch_shared_desktop_frame(root):
    cc = root / "modules/desktop_capture/shared_desktop_frame.cc"
    if not cc.exists():
        return

    text = read(cc)
    if "result->set_gpu_data(gpu_data());" not in text:
        text = replace_once(
            text,
            "  result->CopyFrameInfoFrom(*this);\n  return result;",
            "  result->CopyFrameInfoFrom(*this);\n  result->set_gpu_data(gpu_data());\n  return result;",
            "SharedDesktopFrame::Share gpu_data propagation",
        )
    if "set_gpu_data((*core)->gpu_data());" not in text:
        text = replace_once(
            text,
            "  CopyFrameInfoFrom(*(core_->get()));\n}",
            "  CopyFrameInfoFrom(*(core_->get()));\n  set_gpu_data((*core)->gpu_data());\n}",
            "SharedDesktopFrame constructor gpu_data propagation",
        )
    write_if_changed(cc, text)


def patch_wgc_frame(root):
    header = root / "modules/desktop_capture/win/wgc_desktop_frame.h"
    cc = root / "modules/desktop_capture/win/wgc_desktop_frame.cc"
    if not header.exists() or not cc.exists():
        return

    text = read(header)
    if "std::shared_ptr<DesktopFrameGpuData> gpu_data" not in text:
        text = ensure_include(text, "#include <memory>")
        text = replace_once(
            text,
            "  WgcDesktopFrame(DesktopSize size,\n                  int stride,\n                  std::vector<uint8_t>&& image_data);",
            "  WgcDesktopFrame(DesktopSize size,\n                  int stride,\n                  std::vector<uint8_t>&& image_data,\n                  std::shared_ptr<DesktopFrameGpuData> gpu_data = nullptr);",
            "WGC frame constructor declaration",
        )
        write_if_changed(header, text)

    text = read(cc)
    if "std::shared_ptr<DesktopFrameGpuData> gpu_data" not in text:
        text = ensure_include(text, "#include <memory>")
        text = replace_once(
            text,
            "WgcDesktopFrame::WgcDesktopFrame(DesktopSize size,\n                                 int stride,\n                                 std::vector<uint8_t>&& image_data)\n    : DesktopFrame(size, stride, image_data.data(), nullptr),\n      image_data_(std::move(image_data)) {}",
            "WgcDesktopFrame::WgcDesktopFrame(\n    DesktopSize size,\n    int stride,\n    std::vector<uint8_t>&& image_data,\n    std::shared_ptr<DesktopFrameGpuData> gpu_data)\n    : DesktopFrame(size, stride, image_data.data(), nullptr),\n      image_data_(std::move(image_data)) {\n  set_gpu_data(gpu_data);\n}",
            "WGC frame constructor definition",
        )
        write_if_changed(cc, text)


def patch_wgc_session(root):
    path = root / "modules/desktop_capture/win/wgc_capture_session.cc"
    if not path.exists():
        return

    text = read(path)
    if "WgcD3D11GpuFrameLifetime" not in text:
        text = replace_once(text, "#include <utility>\n", "#include <utility>\n#include <vector>\n", "WGC session vector include")
        text = replace_once(
            text,
            "namespace webrtc {\nnamespace {\n",
            """namespace webrtc {
namespace {

struct WgcD3D11GpuFrameLifetime {
  ComPtr<ID3D11Texture2D> texture;
  ComPtr<ID3D11Device> device;
};

std::shared_ptr<DesktopFrameGpuData> CreateWgcGpuData(
    const ComPtr<ID3D11Texture2D>& texture,
    const ComPtr<ID3D11Device>& device,
    const DesktopSize& size) {
  D3D11_TEXTURE2D_DESC desc = {};
  texture->GetDesc(&desc);
  auto lifetime = std::make_shared<WgcD3D11GpuFrameLifetime>();
  lifetime->texture = texture;
  lifetime->device = device;

  auto gpu_data = std::make_shared<DesktopFrameGpuData>();
  gpu_data->type = DesktopFrameGpuData::Type::kD3D11Texture2D;
  gpu_data->size = size;
  gpu_data->format = static_cast<uint32_t>(desc.Format);
  gpu_data->texture = texture.Get();
  gpu_data->device = device.Get();
  gpu_data->lifetime = lifetime;
  return gpu_data;
}
""",
            "WGC session GPU helpers",
        )

    if "CreateWgcGpuData(texture_2D, d3d11_device_, image_size)" not in text:
        text = replace_if_present(
            text,
            "  DesktopSize image_size(image_width, image_height);\n  if (!queue_.current_frame() ||",
            "  DesktopSize image_size(image_width, image_height);\n  auto gpu_data = CreateWgcGpuData(texture_2D, d3d11_device_, image_size);\n  if (!queue_.current_frame() ||",
        )
        text = replace_if_present(
            text,
            "  DesktopFrame* current_frame = queue_.current_frame();\n  DesktopFrame* previous_frame = queue_.previous_frame();",
            "  DesktopFrame* current_frame = queue_.current_frame();\n  current_frame->set_gpu_data(gpu_data);\n  DesktopFrame* previous_frame = queue_.previous_frame();",
        )
        text = replace_if_present(
            text,
            "  // Transfer ownership of `image_data` to the output_frame.\n  DesktopSize size(image_width, image_height);\n  *output_frame = std::make_unique<WgcDesktopFrame>(size, row_data_length,\n                                                    std::move(image_data));",
            "  // Transfer ownership of `image_data` to the output_frame.\n  DesktopSize size(image_width, image_height);\n  auto gpu_data = CreateWgcGpuData(texture_2D, d3d11_device_, size);\n  *output_frame = std::make_unique<WgcDesktopFrame>(\n      size, row_data_length, std::move(image_data), gpu_data);",
        )
        write_if_changed(path, text)


def patch_dxgi(root):
    texture_h = root / "modules/desktop_capture/win/dxgi_texture.h"
    texture_cc = root / "modules/desktop_capture/win/dxgi_texture.cc"
    duplicator_cc = root / "modules/desktop_capture/win/dxgi_output_duplicator.cc"
    if not texture_h.exists() or not texture_cc.exists() or not duplicator_cc.exists():
        return

    text = read(texture_h)
    if "gpu_data() const" not in text:
        text = replace_once(
            text,
            "  const DesktopFrame& AsDesktopFrame();\n",
            "  const DesktopFrame& AsDesktopFrame();\n\n  const std::shared_ptr<DesktopFrameGpuData>& gpu_data() const {\n    return gpu_data_;\n  }\n",
            "DXGI texture gpu_data accessor",
        )
        text = replace_once(
            text,
            "  std::unique_ptr<DesktopFrame> frame_;\n",
            "  std::unique_ptr<DesktopFrame> frame_;\n  std::shared_ptr<DesktopFrameGpuData> gpu_data_;\n",
            "DXGI texture gpu_data member",
        )
        write_if_changed(texture_h, text)

    text = read(texture_cc)
    if "DxgiD3D11GpuFrameLifetime" not in text:
        text = ensure_include(text, "#include <memory>")
        text = ensure_include(text, "#include <utility>")
        text = replace_once(
            text,
            "namespace {\n",
            """namespace {

struct DxgiD3D11GpuFrameLifetime {
  ComPtr<ID3D11Texture2D> texture;
  ComPtr<ID3D11Device> device;
};
""",
            "DXGI texture lifetime helper",
        )
        text = replace_once(
            text,
            "  D3D11_TEXTURE2D_DESC desc = {0};\n  texture->GetDesc(&desc);\n  desktop_size_.set(desc.Width, desc.Height);\n\n  return CopyFromTexture(frame_info, texture.Get());",
            """  D3D11_TEXTURE2D_DESC desc = {0};
  texture->GetDesc(&desc);
  desktop_size_.set(desc.Width, desc.Height);

  ComPtr<ID3D11Device> device;
  texture->GetDevice(device.GetAddressOf());
  auto lifetime = std::make_shared<DxgiD3D11GpuFrameLifetime>();
  lifetime->texture = texture;
  lifetime->device = device;
  auto gpu_data = std::make_shared<DesktopFrameGpuData>();
  gpu_data->type = DesktopFrameGpuData::Type::kD3D11Texture2D;
  gpu_data->size = desktop_size_;
  gpu_data->format = static_cast<uint32_t>(desc.Format);
  gpu_data->texture = texture.Get();
  gpu_data->device = device.Get();
  gpu_data->lifetime = lifetime;
  gpu_data_ = gpu_data;

  return CopyFromTexture(frame_info, texture.Get());""",
            "DXGI texture GPU descriptor creation",
        )
        write_if_changed(texture_cc, text)

    text = read(duplicator_cc)
    if "target->set_gpu_data(texture_->gpu_data());" not in text:
        text = replace_once(
            text,
            "  if (!DesktopRect::MakeSize(target->size())\n           .ContainsRect(GetTranslatedDesktopRect(offset))) {",
            "  target->clear_gpu_data();\n  if (!DesktopRect::MakeSize(target->size())\n           .ContainsRect(GetTranslatedDesktopRect(offset))) {",
            "DXGI duplicator clear gpu_data",
        )
        text = replace_once(
            text,
            "    updated_region.Translate(offset.x(), offset.y());\n    target->mutable_updated_region()->AddRegion(updated_region);",
            "    if (rotation_ == Rotation::CLOCK_WISE_0 && offset.is_zero() &&\n        target->size().equals(texture_->desktop_size())) {\n      target->set_gpu_data(texture_->gpu_data());\n    }\n    updated_region.Translate(offset.x(), offset.y());\n    target->mutable_updated_region()->AddRegion(updated_region);",
            "DXGI duplicator attach gpu_data",
        )
        write_if_changed(duplicator_cc, text)


def patch_pipewire(root):
    path = root / "modules/desktop_capture/linux/wayland/shared_screencast_stream.cc"
    if not path.exists():
        return

    text = read(path)
    if "ProcessDMABuffer" not in text:
        return

    if "DmaBufGpuFrameLifetime" not in text:
        text = replace_once(text, "#include <sys/types.h>\n", "#include <sys/types.h>\n#include <unistd.h>\n", "PipeWire unistd include")
        text = replace_once(
            text,
            "namespace webrtc {\n\nconst int kBytesPerPixel = 4;",
            """namespace webrtc {

struct DmaBufGpuFrameLifetime {
  ~DmaBufGpuFrameLifetime() {
    for (int fd : fds) {
      if (fd >= 0) {
        close(fd);
      }
    }
  }

  std::vector<int> fds;
};

const int kBytesPerPixel = 4;""",
            "PipeWire DMA-BUF lifetime helper",
        )

    if "BuildDmaBufGpuData" not in text:
        text = replace_once(
            text,
            "  bool ProcessDMABuffer(pw_buffer* buffer,\n                        DesktopFrame& frame,\n                        const DesktopVector& offset);",
            "  bool ProcessDMABuffer(pw_buffer* buffer,\n                        DesktopFrame& frame,\n                        const DesktopVector& offset);\n  std::shared_ptr<DesktopFrameGpuData> BuildDmaBufGpuData(\n      const spa_buffer* spa_buffer,\n      const DesktopVector& offset,\n      const DesktopSize& frame_size);",
            "PipeWire BuildDmaBufGpuData declaration",
        )
        text = replace_once(
            text,
            "\nvoid SharedScreenCastStreamPrivate::ConvertRGBxToBGRx(uint8_t* frame,",
            r"""
std::shared_ptr<DesktopFrameGpuData>
SharedScreenCastStreamPrivate::BuildDmaBufGpuData(
    const spa_buffer* spa_buffer,
    const DesktopVector& offset,
    const DesktopSize& frame_size) {
  auto lifetime = std::make_shared<DmaBufGpuFrameLifetime>();
  auto gpu_data = std::make_shared<DesktopFrameGpuData>();
  gpu_data->type = DesktopFrameGpuData::Type::kDmaBuf;
  gpu_data->size = frame_size;
  gpu_data->offset = offset;
  gpu_data->format = spa_video_format_.format;
  gpu_data->modifier = modifier_;

  for (uint32_t i = 0; i < spa_buffer->n_datas; ++i) {
    int dup_fd = dup(static_cast<int>(spa_buffer->datas[i].fd));
    if (dup_fd < 0) {
      RTC_LOG(LS_ERROR) << "Failed to dup DMA-BUF fd: " << std::strerror(errno);
      return nullptr;
    }
    lifetime->fds.push_back(dup_fd);
    DesktopFrameGpuData::DmaBufPlane plane;
    plane.fd = dup_fd;
    plane.stride = static_cast<uint32_t>(spa_buffer->datas[i].chunk->stride);
    plane.offset = static_cast<uint32_t>(spa_buffer->datas[i].chunk->offset);
    gpu_data->dma_buf_planes.push_back(plane);
  }

  gpu_data->lifetime = lifetime;
  return gpu_data;
}

void SharedScreenCastStreamPrivate::ConvertRGBxToBGRx(uint8_t* frame,""",
            "PipeWire BuildDmaBufGpuData definition",
        )

    if "auto gpu_data = BuildDmaBufGpuData" not in text:
        text = replace_once(
            text,
            "  if (spa_buffer->datas[0].type == SPA_DATA_MemFd) {\n    bufferProcessed =\n        ProcessMemFDBuffer(buffer, *queue_.current_frame(), offset);\n  } else if (spa_buffer->datas[0].type == SPA_DATA_DmaBuf) {\n    bufferProcessed = ProcessDMABuffer(buffer, *queue_.current_frame(), offset);\n  }",
            "  queue_.current_frame()->clear_gpu_data();\n  if (spa_buffer->datas[0].type == SPA_DATA_MemFd) {\n    bufferProcessed =\n        ProcessMemFDBuffer(buffer, *queue_.current_frame(), offset);\n  } else if (spa_buffer->datas[0].type == SPA_DATA_DmaBuf) {\n    bufferProcessed = ProcessDMABuffer(buffer, *queue_.current_frame(), offset);\n    if (bufferProcessed) {\n      auto gpu_data = BuildDmaBufGpuData(\n          spa_buffer, offset, queue_.current_frame()->size());\n      if (gpu_data) {\n        queue_.current_frame()->set_gpu_data(gpu_data);\n      }\n    }\n  }",
            "PipeWire attach gpu_data in m144 process path",
        )
        text = replace_if_present(
            text,
            "  queue_.current_frame()->CopyPixelsFrom(\n      updated_src, (src_stride - (kBytesPerPixel * x_offset)),\n      DesktopRect::MakeWH(frame_size_.width(), frame_size_.height()));",
            "  queue_.current_frame()->clear_gpu_data();\n  queue_.current_frame()->CopyPixelsFrom(\n      updated_src, (src_stride - (kBytesPerPixel * x_offset)),\n      DesktopRect::MakeWH(frame_size_.width(), frame_size_.height()));",
        )
        write_if_changed(path, text)


def patch_single_screen_capture(root):
    directx_h = root / "modules/desktop_capture/win/screen_capturer_win_directx.h"
    directx_cc = root / "modules/desktop_capture/win/screen_capturer_win_directx.cc"
    if directx_h.exists():
        text = read(directx_h)
        text = replace_if_present(
            text,
            "  SourceId current_screen_id_ = kFullDesktopScreenId;",
            "  SourceId current_screen_id_ = 0;",
        )
        write_if_changed(directx_h, text)

    if directx_cc.exists():
        text = read(directx_cc)
        text = replace_if_present(
            text,
            "  DxgiDuplicatorController::Result result;\n  if (current_screen_id_ == kFullDesktopScreenId) {\n    result = controller_->Duplicate(frames.current_frame());\n  } else {\n    result = controller_->DuplicateMonitor(frames.current_frame(),\n                                           current_screen_id_);\n  }",
            "  DxgiDuplicatorController::Result result =\n      controller_->DuplicateMonitor(frames.current_frame(), current_screen_id_);",
        )
        text = replace_if_present(
            text,
            "bool ScreenCapturerWinDirectx::SelectSource(SourceId id) {\n  if (id == kFullDesktopScreenId) {\n    current_screen_id_ = id;\n    return true;\n  }\n\n  std::vector<std::string> device_names;",
            "bool ScreenCapturerWinDirectx::SelectSource(SourceId id) {\n  if (id == kFullDesktopScreenId) {\n    id = 0;\n  }\n\n  std::vector<std::string> device_names;",
        )
        write_if_changed(directx_cc, text)

    for name in ("gdi", "magnifier"):
        header = root / f"modules/desktop_capture/win/screen_capturer_win_{name}.h"
        cc = root / f"modules/desktop_capture/win/screen_capturer_win_{name}.cc"
        if header.exists():
            text = read(header)
            text = replace_if_present(
                text,
                "  SourceId current_screen_id_ = kFullDesktopScreenId;",
                "  SourceId current_screen_id_ = 0;",
            )
            text = replace_if_present(
                text,
                "  ScreenId current_screen_id_ = kFullDesktopScreenId;",
                "  ScreenId current_screen_id_ = 0;",
            )
            write_if_changed(header, text)

        if cc.exists():
            class_name = "ScreenCapturerWinGdi" if name == "gdi" else "ScreenCapturerWinMagnifier"
            text = read(cc)
            old = f"""bool {class_name}::SelectSource(SourceId id) {{
  std::wstring device_key;
  bool valid = IsScreenValid(id, &device_key);
  if (valid) {{
    current_screen_id_ = id;
    current_device_key_ = device_key;
  }} else {{
    current_screen_id_ = kFullDesktopScreenId;
    current_device_key_ = std::nullopt;
  }}
  return valid;
}}"""
            new = f"""bool {class_name}::SelectSource(SourceId id) {{
  if (id == kFullDesktopScreenId) {{
    id = 0;
  }}

  std::wstring device_key;
  if (!IsScreenValid(id, &device_key)) {{
    return false;
  }}

  current_screen_id_ = id;
  current_device_key_ = device_key;
  return true;
}}"""
            text = replace_if_present(text, old, new)
            old_m109_gdi = """bool ScreenCapturerWinGdi::SelectSource(SourceId id) {
  bool valid = IsScreenValid(id, &current_device_key_);
  if (valid)
    current_screen_id_ = id;
  return valid;
}"""
            new_m109_gdi = """bool ScreenCapturerWinGdi::SelectSource(SourceId id) {
  if (id == kFullDesktopScreenId) {
    id = 0;
  }

  bool valid = IsScreenValid(id, &current_device_key_);
  if (valid)
    current_screen_id_ = id;
  return valid;
}"""
            old_m109_magnifier = """bool ScreenCapturerWinMagnifier::SelectSource(SourceId id) {
  if (IsScreenValid(id, &current_device_key_)) {
    current_screen_id_ = id;
    return true;
  }

  return false;
}"""
            new_m109_magnifier = """bool ScreenCapturerWinMagnifier::SelectSource(SourceId id) {
  if (id == kFullDesktopScreenId) {
    id = 0;
  }

  if (IsScreenValid(id, &current_device_key_)) {
    current_screen_id_ = id;
    return true;
  }

  return false;
}"""
            text = replace_if_present(text, old_m109_gdi, new_m109_gdi)
            text = replace_if_present(text, old_m109_magnifier, new_m109_magnifier)
            write_if_changed(cc, text)

    wgc_source = root / "modules/desktop_capture/win/wgc_capture_source.cc"
    if wgc_source.exists():
        text = read(wgc_source)
        text = replace_if_present(
            text,
            "  HMONITOR hmon;\n  if (GetHmonitorFromDeviceIndex(GetSourceId(), &hmon))\n    hmonitor_ = hmon;",
            "  const DesktopCapturer::SourceId screen_source_id =\n      GetSourceId() == kFullDesktopScreenId ? 0 : GetSourceId();\n  HMONITOR hmon;\n  if (GetHmonitorFromDeviceIndex(screen_source_id, &hmon))\n    hmonitor_ = hmon;",
        )
        write_if_changed(wgc_source, text)

    x11 = root / "modules/desktop_capture/linux/x11/screen_capturer_x11.cc"
    if x11.exists():
        text = read(x11)
        text = replace_if_present(
            text,
            "    if (selected_monitor_name_ == static_cast<Atom>(kFullDesktopScreenId)) {\n      selected_monitor_rect_ =\n          DesktopRect::MakeSize(x_server_pixel_buffer_.window_size());\n      return;\n    }",
            "    if (selected_monitor_name_ == static_cast<Atom>(kFullDesktopScreenId)) {\n      if (num_monitors_ > 0) {\n        selected_monitor_name_ = monitors_[0].name;\n      } else {\n        selected_monitor_rect_ = DesktopRect::MakeWH(0, 0);\n        return;\n      }\n    }",
        )
        text = replace_if_present(
            text,
            "  if (!use_randr_ || id == kFullDesktopScreenId) {\n    selected_monitor_name_ = kFullDesktopScreenId;\n    selected_monitor_rect_ =\n        DesktopRect::MakeSize(x_server_pixel_buffer_.window_size());\n    return true;\n  }\n\n  for (int i = 0; i < num_monitors_; ++i) {",
            "  if (!use_randr_) {\n    selected_monitor_name_ = 0;\n    selected_monitor_rect_ = DesktopRect::MakeWH(0, 0);\n    return false;\n  }\n\n  if (id == kFullDesktopScreenId) {\n    if (num_monitors_ <= 0) {\n      selected_monitor_name_ = 0;\n      selected_monitor_rect_ = DesktopRect::MakeWH(0, 0);\n      return false;\n    }\n    id = static_cast<SourceId>(monitors_[0].name);\n  }\n\n  for (int i = 0; i < num_monitors_; ++i) {",
        )
        write_if_changed(x11, text)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch_desktop_gpu_frames.py <webrtc-src>")
    root = Path(sys.argv[1]).resolve()
    patch_desktop_frame(root)
    patch_shared_desktop_frame(root)
    patch_wgc_frame(root)
    patch_wgc_session(root)
    patch_dxgi(root)
    patch_pipewire(root)
    patch_single_screen_capture(root)


if __name__ == "__main__":
    main()
