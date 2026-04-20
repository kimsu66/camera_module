`timescale 1ns / 1ps

module tb_ov7670_init;

    reg clk    = 0;
    reg resetn = 0;

    wire scl;
    wire sda;
    wire done;

    // DUT 내부 신호
    wire [4:0] _state     = DUT.state;
    wire [5:0] _reg_index = DUT.reg_index;
    wire       _sda_oe    = DUT.sda_oe;
    wire       _sda_out   = DUT.sda_out;
    wire       _tick      = DUT.tick;

    ov7670_init DUT (
        .clk(clk), .resetn(resetn),
        .scl(scl), .sda(sda), .done(done)
    );

    always #5 clk = ~clk;  // 100MHz

    // ── SCCB 수신: state 직접 관찰 ──────────────────────────────────
    // S_STOP2(13)에 진입하는 순간 shreg에 최종값이 들어있음
    // 대신 DUT 내부 rom에서 직접 읽어서 검증하는 방식이 더 정확
    wire [7:0] rom_addr_val = DUT.rom_addr[_reg_index];
    wire [7:0] rom_data_val = DUT.rom_data[_reg_index];

    reg [4:0] prev_state = 0;
    integer   tx_count   = 0;
    integer   pass_cnt   = 0;
    integer   fail_cnt   = 0;

    // S_STOP2 진입 순간 = 레지스터 1개 전송 완료
    // reg_index는 STOP2에서 아직 증가 전이므로 현재 전송한 인덱스
    always @(posedge clk) begin
        prev_state <= _state;

        // STOP1(12) → STOP2(13) 전이 = 전송 완료
        if (prev_state == 5'd12 && _state == 5'd13) begin
            $display("  [%0d] REG=0x%h  DAT=0x%h  (rom[%0d])",
                     tx_count,
                     DUT.rom_addr[_reg_index],
                     DUT.rom_data[_reg_index],
                     _reg_index);
            tx_count = tx_count + 1;
        end
    end

    integer timeout;

    initial begin
        $display("================================================");
        $display(" tb_ov7670_init (clk=100MHz / SCCB tick=200kHz)");
        $display("================================================\n");

        // [1] 리셋
        $display("[1] resetn=0 -> reset");
        resetn = 0;
        repeat(20) @(posedge clk);
        $display("    scl=%b sda=%b done=%b state=%0d",
                 scl, sda, done, _state);
        $display("    기대: scl=1 sda=1 done=0 state=0(IDLE)\n");

        // [2] 시작
        $display("[2] resetn=1 -> 초기화 시작");
        $display("    기대 전송 순서:\n");
        @(posedge clk); resetn = 1;

        // done 될 때까지 대기
        timeout = 0;
        while (!done && timeout < 200_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        $display("");

        // [3] 결과 검증
        $display("[3] 전송 결과 검증");
        $display("    전송 완료 수: %0d / 31", tx_count);

        if (done)
            $display("    done=1 -> 정상 완료");
        else
            $display("    [FAIL] done=1 미발생");

        if (tx_count == 31)
            $display("    [PASS] 31개 모두 전송");
        else
            $display("    [FAIL] 전송 수 불일치");

        // ROM 내용 전체 출력 (기대값 확인용)
        $display("");
        $display("[4] ROM 저장 내용 전체 (실제 전송 예정값)");
        begin : rom_print
            integer i;
            for (i = 0; i <= 30; i = i + 1)
                $display("    rom[%0d] REG=0x%h DAT=0x%h",
                         i, DUT.rom_addr[i], DUT.rom_data[i]);
        end

        $display("");
        $display("[5] 최종 내부 상태");
        $display("    state=%0d reg_index=%0d done=%b",
                 _state, _reg_index, done);
        $display("    state=15(S_DONE) reg_index=30 done=1 이면 정상\n");

        $display("================================================");
        $display(" 신호별 정상 동작 기준");
        $display("  clk   : 100MHz 입력");
        $display("  tick  : 100MHz/500 = 200kHz. 상태머신 전진 기준");
        $display("  SCL   : tick마다 HIGH/LOW. 실효 100kHz");
        $display("  SDA   : SCL LOW 구간에서 변경, HIGH에서 안정");
        $display("  START : SCL=1일때 SDA 하강");
        $display("  STOP  : SCL=1일때 SDA 상승");
        $display("  ACK   : 9번째 SCL에서 SDA=Hi-Z (don't care)");
        $display("  done  : 31개 전송 완료 후 HIGH, 이후 계속 유지");
        $display("  DEV   : 항상 0x42 (OV7670 write address)");
        $display("================================================");
        $finish;
    end

endmodule