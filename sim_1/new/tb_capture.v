`timescale 1ns / 1ps

module tb_ov7670_capture;

    // ── 입력 신호 (우리가 카메라 흉내내서 줌) ──────────────────────
    reg        pclk  = 0;
    reg        vsync = 0;
    reg        href  = 0;
    reg  [7:0] d     = 0;

    // ── 출력 신호 (capture 모듈이 내보내는 것) ─────────────────────
    wire [15:0] pixel_data;
    wire        pixel_valid;
    wire [16:0] addr;

    // ── DUT 내부 신호 직접 꺼내기  ──────────
    wire        _byte_sel  = DUT.byte_sel;   // 0: 첫번째 바이트 대기, 1: 두번째 바이트 대기
    wire  [7:0] _high_byte = DUT.high_byte;  // 첫번째 바이트 저장되는 곳
    wire  [9:0] _x         = DUT.x;          // 현재 열 카운터 (0~639)
    wire  [8:0] _y         = DUT.y;          // 현재 행 카운터 (0~479)
    wire        _vsync_d   = DUT.vsync_d;    // vsync 1클럭 지연 (상승엣지 감지용)

    // ── DUT 연결 ────────────────────────────────────────────────────
    ov7670_capture DUT (
        .pclk(pclk), .vsync(vsync), .href(href), .d(d),
        .pixel_data(pixel_data), .pixel_valid(pixel_valid), .addr(addr)
    );

    // 12.5MHz: 주기 80ns, half period 40ns
    always #40 pclk = ~pclk;

    // ── VCD 덤프: tb + DUT 내부 신호 전부 ──────────────────────────
    initial begin
        $dumpfile("tb_capture.vcd");
        $dumpvars(0, tb_ov7670_capture);  // tb 전체 (내부 wire 포함)
        $dumpvars(0, DUT);                // DUT 내부 신호도 전부
    end

    // ── pixel_valid 뜰 때마다 콘솔 출력 ────────────────────────────
    always @(posedge pclk) begin
        if (pixel_valid)
            $display("  >> PIXEL!  x=%0d y=%0d | data=0x%h | addr=%0d",
                     _x, _y, pixel_data, addr);
    end

    // ── 태스크: 픽셀 1개 전송 (2바이트) ────────────────────────────
    // COM10[2]=0 이므로 VSYNC/데이터 변화는 negedge 기준
    // → negedge에 d 세팅, posedge에 DUT가 읽음
    task send_pixel;
        input [7:0] b0;  // byte0: {R[4:0], G[5:3]}
        input [7:0] b1;  // byte1: {G[2:0], B[4:0]}
        begin
            @(negedge pclk); d = b0;   // negedge에 세팅 (tPDV 반영)
            @(posedge pclk);           // DUT가 b0 읽음 → high_byte에 저장
            @(negedge pclk); d = b1;
            @(posedge pclk);           // DUT가 b1 읽음 → pixel 완성
        end
    endtask

    // ── 태스크: 나머지 행 채워서 y 다음 행으로 넘기기 ───────────────
    task advance_row;
        input integer from_x;  // 현재 x 위치
        integer j;
        begin
            @(negedge pclk); href = 0;
            for (j = from_x; j < 639; j = j + 1) begin
                @(negedge pclk); href = 1; d = 8'hDD;
                @(posedge pclk);
                @(negedge pclk);           d = 8'hEE;
                @(posedge pclk);
            end
            // x=639 마지막 바이트 → posedge에서 x=0, y+1
            @(negedge pclk); d = 8'hDD;
            @(posedge pclk);
            @(negedge pclk); d = 8'hEE;
            @(posedge pclk);
            @(negedge pclk); href = 0;
            repeat(4) @(posedge pclk);
        end
    endtask

    // ── 메인 시뮬레이션 ─────────────────────────────────────────────
    initial begin
        $display("==============================================");
        $display(" tb_ov7670_capture  (pclk=12.5MHz)");
        $display(" GTKWave 신호 추가 순서:");
        $display("   pclk / vsync / _vsync_d");
        $display("   href / d");
        $display("   _byte_sel / _high_byte");
        $display("   pixel_valid / pixel_data / addr");
        $display("   _x / _y");
        $display("==============================================\n");

        // ── [1] VSYNC 펄스: 새 프레임 시작 ─────────────────────────
        // COM10[2]=0 → VSYNC는 negedge에서 바뀜
        $display("[1] VSYNC 펄스 (negedge에서 올리고 내림)");
        $display("    기대: vsync 상승엣지 → x=0, y=0, byte_sel=0 리셋");
        @(negedge pclk); vsync = 1;
        repeat(6) @(posedge pclk);
        @(negedge pclk); vsync = 0;
        // vsync_d가 따라올 때까지 대기
        repeat(6) @(posedge pclk);
        $display("    완료 (_x=%0d _y=%0d _byte_sel=%0d)\n", _x, _y, _byte_sel);

        // ── [2] y=0 (짝수행): 픽셀 4개 ────────────────────────────
        $display("[2] y=0 짝수행, href=1");
        @(negedge pclk); href = 1;

        // x=0, y=0: 짝수+짝수 → pixel_valid=1, addr=0
        // 빨강 R=31: byte0={11111,000}=0xF8, byte1={000,00000}=0x00
        $display("  x=0 y=0 | 빨강(R=31) | 기대: pixel_valid=1, addr=0");
        send_pixel(8'hF8, 8'h00);

        // x=1, y=0: 홀수열 → pixel_valid=0
        $display("  x=1 y=0 | (홀수열)   | 기대: pixel_valid=0");
        send_pixel(8'hAA, 8'hBB);

        // x=2, y=0: 짝수+짝수 → pixel_valid=1, addr=1
        // 파랑 B=31: byte0={00000,000}=0x00, byte1={000,11111}=0x1F
        $display("  x=2 y=0 | 파랑(B=31) | 기대: pixel_valid=1, addr=1");
        send_pixel(8'h00, 8'h1F);

        // x=3, y=0: 홀수열 → pixel_valid=0
        $display("  x=3 y=0 | (홀수열)   | 기대: pixel_valid=0\n");
        send_pixel(8'hCC, 8'hDD);

        // ── [3] y=0 → y=1 행 이동 ──────────────────────────────────
        $display("[3] x=4부터 채워서 y=1로 이동...");
        advance_row(4);
        $display("    완료 (_y=%0d)\n", _y);

        // ── [4] y=1 (홀수행): 전부 스킵 ────────────────────────────
        $display("[4] y=1 홀수행 — >> 없으면 정상");
        @(negedge pclk); href = 1;
        $display("  x=0 y=1 | 기대: pixel_valid=0");
        send_pixel(8'hFF, 8'hFF);
        $display("  x=1 y=1 | 기대: pixel_valid=0\n");
        send_pixel(8'hFF, 8'hFF);

        // y=1 → y=2
        advance_row(2);
        $display("    (_y=%0d 진입)\n", _y);

        // ── [5] y=2 (짝수행): addr=320 확인 ────────────────────────
        $display("[5] y=2 짝수행");
        $display("    기대 addr = 1*320+0 = 320");
        @(negedge pclk); href = 1;

        // 초록 G=63: byte0={00000,111}=0x07, byte1={111,00000}=0xE0
        $display("  x=0 y=2 | 초록(G=63) | 기대: pixel_valid=1, addr=320");
        send_pixel(8'h07, 8'hE0);

        $display("  x=1 y=2 | (홀수열)   | 기대: pixel_valid=0");
        send_pixel(8'h11, 8'h22);

        @(negedge pclk); href = 0;
        repeat(6) @(posedge pclk);

        $finish;
    end

endmodule