# camera_module

OV7670 카메라 모듈을 Verilog로 구현한 FPGA 프로젝트.

## 개요

OV7670 이미지 센서와 FPGA를 연동하여 실시간 영상 캡처 및 출력을 구현한 프로젝트이다. SCCB(Serial Camera Control Bus) 프로토콜을 통해 카메라를 초기화하고, 픽셀 데이터를 캡처하여 VGA 디스플레이에 출력한다.

## 하드웨어 구성

| 구성 요소 | 설명 |
|---|---|
| FPGA 보드 | Xilinx / Altera 계열 FPGA |
| 카메라 모듈 | OV7670 (640×480, QVGA, RGB565) |
| 디스플레이 | VGA 모니터 |

## 주요 기능

- **SCCB 인터페이스**: OV7670 카메라 레지스터 초기화 및 설정
- **픽셀 데이터 캡처**: VSYNC / HREF / PCLK 신호 기반 영상 수신
- **FIFO 버퍼**: 카메라 클럭 도메인과 VGA 클럭 도메인 간 데이터 동기화
- **VGA 출력**: 640×480 해상도 실시간 디스플레이
- **클럭 관리**: PLL / DCM을 통한 24MHz 카메라 클럭 및 25MHz VGA 픽셀 클럭 생성

## 모듈 구조

```
camera_module/
├── top.v                  # 최상위 모듈 (전체 시스템 연결)
├── ov7670_capture.v       # 카메라 픽셀 데이터 캡처 모듈
├── ov7670_controller.v    # SCCB 기반 카메라 초기화 컨트롤러
├── sccb.v                 # SCCB(I2C 유사) 통신 모듈
├── fifo.v                 # 클럭 도메인 교차용 FIFO 버퍼
├── vga.v                  # VGA 타이밍 및 출력 모듈
└── clk_wiz.v              # 클럭 생성 모듈 (PLL)
```

## 신호 흐름

```
OV7670
 PCLK / HREF / VSYNC / D[7:0]
        │
        ▼
 ov7670_capture.v
  (픽셀 데이터 수신)
        │
        ▼
    fifo.v
  (클럭 도메인 동기화)
        │
        ▼
    vga.v
  (640×480 VGA 출력)
        │
        ▼
   VGA 모니터
```

## 핀 설정

| 신호 | FPGA 핀 | 방향 | 설명 |
|---|---|---|---|
| `clk` | - | Input | 시스템 클럭 (50MHz) |
| `rst_n` | - | Input | 비동기 리셋 (Active Low) |
| `cam_pclk` | - | Input | 카메라 픽셀 클럭 |
| `cam_vsync` | - | Input | 수직 동기 신호 |
| `cam_href` | - | Input | 수평 데이터 유효 신호 |
| `cam_data[7:0]` | - | Input | 카메라 픽셀 데이터 |
| `cam_xclk` | - | Output | 카메라 입력 클럭 (24MHz) |
| `sccb_sclk` | - | Output | SCCB 클럭 |
| `sccb_sdat` | - | Inout | SCCB 데이터 |
| `vga_hsync` | - | Output | VGA 수평 동기 |
| `vga_vsync` | - | Output | VGA 수직 동기 |
| `vga_r[3:0]` | - | Output | VGA 빨강 채널 |
| `vga_g[3:0]` | - | Output | VGA 초록 채널 |
| `vga_b[3:0]` | - | Output | VGA 파랑 채널 |

## 빌드 및 합성

### Xilinx Vivado

1. Vivado 실행 후 새 프로젝트 생성
2. 모든 `.v` 파일을 프로젝트에 추가
3. 타겟 FPGA 디바이스 선택
4. 제약 파일(`.xdc`)에서 핀 설정
5. **Run Synthesis → Run Implementation → Generate Bitstream** 순서로 실행
6. FPGA에 비트스트림 다운로드

### Xilinx ISE

1. ISE Project Navigator에서 새 프로젝트 생성
2. 모든 `.v` 파일과 UCF 제약 파일 추가
3. **Synthesize → Implement → Generate Programming File** 순서로 실행

## 카메라 초기화 설정

OV7670은 전원 인가 후 SCCB를 통한 레지스터 초기화가 필요하다. 주요 설정값은 아래와 같다.

| 레지스터 | 주소 | 설정값 | 설명 |
|---|---|---|---|
| COM7 | 0x12 | 0x80 | 소프트웨어 리셋 |
| COM7 | 0x12 | 0x04 | RGB 출력 모드 |
| COM15 | 0x40 | 0xD0 | RGB565 포맷 |
| CLKRC | 0x11 | 0x01 | 클럭 분주비 설정 |

## 참고 자료

- [OV7670 데이터시트](https://www.voti.nl/docs/OV7670.pdf)
- [OV7670 구현 가이드 (FPGA4FUN)](http://www.fpga4fun.com/PongGame.html)
- [SCCB 프로토콜 사양](https://www.ovt.com/download/soapbox/2376)
