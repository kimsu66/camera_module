`timescale 1ns / 1ps

module tb_frame_buffer;

    // ── 쓰기 포트 (capture 도메인, 12.5MHz) ────────────────────────
    reg         clk_write  = 0;
    reg         write_en   = 0;
    reg  [16:0] write_addr = 0;
    reg   [7:0] pixel_in   = 0;

    // ── 읽기 포트 (VGA 도메인, 25MHz) ──────────────────────────────
    reg         clk_read   = 0;
    reg  [16:0] read_addr  = 0;

    // ── 출력 ────────────────────────────────────────────────────────
    wire  [7:0] pixel_out;

    // ── DUT ─────────────────────────────────────────────────────────
    frame_buffer DUT (
        .clk_write  (clk_write),
        .write_en   (write_en),
        .write_addr (write_addr),
        .pixel_in   (pixel_in),
        .clk_read   (clk_read),
        .read_addr  (read_addr),
        .pixel_out  (pixel_out)
    );

    // clk_write: 12.5MHz (80ns 주기, half=40ns)
    always #40 clk_write = ~clk_write;

    // clk_read:  25MHz  (40ns 주기, half=20ns)
    always #20 clk_read  = ~clk_read;

    // ── 테스트 결과 카운터 ──────────────────────────────────────────
    integer pass = 0;
    integer fail = 0;

    task check;
        input [7:0]  got;
        input [7:0]  expected;
        input [16:0] addr_val;
        input [31:0] test_num;
        begin
            if (got === expected) begin
                $display("  [PASS] test%0d | addr=%0d | pixel_out=0x%h (기대 0x%h)",
                         test_num, addr_val, got, expected);
                pass = pass + 1;
            end else begin
                $display("  [FAIL] test%0d | addr=%0d | pixel_out=0x%h (기대 0x%h) ← 불일치!",
                         test_num, addr_val, got, expected);
                fail = fail + 1;
            end
        end
    endtask

    integer i;

    initial begin
        $display("============================================");
        $display(" tb_frame_buffer");
        $display(" clk_write=12.5MHz  clk_read=25MHz");
        $display("============================================\n");

        // ── [1] 기본 쓰기 → 읽기, 1클럭 레이턴시 확인 ──────────────
        // 핵심: read_addr 준 다음 clk_read posedge에서 pixel_out이 나옴
        //       즉 read_addr 바꾼 뒤 1클럭 기다려야 유효한 값
        $display("[1] 기본 쓰기 후 읽기 - 1클럭 레이턴시 확인");

        // addr=0 에 0xAB 쓰기
        @(negedge clk_write);
        write_en = 1; write_addr = 17'd0; pixel_in = 8'hAB;
        @(posedge clk_write);   // 이 posedge에서 mem[0] = 0xAB 저장

        @(negedge clk_write);
        write_en = 0;

        // read_addr=0 세팅
        @(negedge clk_read);
        read_addr = 17'd0;
        @(posedge clk_read);    // 이 posedge에서 pixel_out = mem[0] 래치
        #1;                     // nonblocking 업데이트 대기
        check(pixel_out, 8'hAB, 17'd0, 1);

        $display("");

        // ── [2] 여러 주소에 쓰고 순서대로 읽기 ─────────────────────
        $display("[2] 여러 주소 쓰기 후 순서대로 읽기");

        // addr=0~4 에 0x10~0x50 쓰기
        for (i = 0; i < 5; i = i + 1) begin
            @(negedge clk_write);
            write_en   = 1;
            write_addr = i;
            pixel_in   = 8'h10 * (i + 1);  // 0x10, 0x20, 0x30, 0x40, 0x50
            @(posedge clk_write);
        end
        @(negedge clk_write); write_en = 0;

        // 순서대로 읽기
        for (i = 0; i < 5; i = i + 1) begin
            @(negedge clk_read);
            read_addr = i;
            @(posedge clk_read); #1;
            check(pixel_out, 8'h10 * (i + 1), i, i + 2);
        end

        $display("");

        // ── [3] 경계 주소 확인 (첫번째, 마지막) ────────────────────
        $display("[3] 경계 주소 - addr=0, addr=76799");

        @(negedge clk_write);
        write_en = 1; write_addr = 17'd0;     pixel_in = 8'hFF;
        @(posedge clk_write);
        @(negedge clk_write);
        write_addr = 17'd76799; pixel_in = 8'hEE;
        @(posedge clk_write);
        @(negedge clk_write); write_en = 0;

        @(negedge clk_read); read_addr = 17'd0;
        @(posedge clk_read); #1;
        check(pixel_out, 8'hFF, 17'd0, 8);

        @(negedge clk_read); read_addr = 17'd76799;
        @(posedge clk_read); #1;
        check(pixel_out, 8'hEE, 17'd76799, 9);

        $display("");

        // ── [4] write_en=0 일 때 덮어쓰기 안 되는지 확인 ───────────
        $display("[4] write_en=0 - 기존 값 유지 확인");

        // addr=100에 0xCC 먼저 씀
        @(negedge clk_write);
        write_en = 1; write_addr = 17'd100; pixel_in = 8'hCC;
        @(posedge clk_write);

        // write_en=0 인 상태에서 다른 값으로 시도
        @(negedge clk_write);
        write_en = 0; write_addr = 17'd100; pixel_in = 8'h00;
        @(posedge clk_write);  // 이 클럭엔 write_en=0 이라 무시됨

        // 읽어서 0xCC가 유지되는지 확인
        @(negedge clk_read); read_addr = 17'd100;
        @(posedge clk_read); #1;
        check(pixel_out, 8'hCC, 17'd100, 10);

        $display("");

        // ── [5] dual clock: 쓰기 중에 읽기 (다른 주소) ─────────────
        // 쓰기 클럭(12.5MHz)이 느리고 읽기 클럭(25MHz)이 빠른 상황
        // 쓰기가 진행되는 동안 다른 주소를 읽으면 이전 값이 유지되어야 함
        $display("[5] dual clock 동작 - 쓰는 동안 다른 주소 읽기");

        // addr=200에 0xBB 미리 씀
        @(negedge clk_write);
        write_en = 1; write_addr = 17'd200; pixel_in = 8'hBB;
        @(posedge clk_write);
        @(negedge clk_write); write_en = 0;

        // addr=200 읽으면서 동시에 addr=201에 쓰기 시작
        @(negedge clk_read);  read_addr  = 17'd200;
        @(negedge clk_write); write_en = 1; write_addr = 17'd201; pixel_in = 8'hAA;
        @(posedge clk_read); #1;
        // addr=200은 0xBB 유지, addr=201 쓰기는 독립적으로 진행
        check(pixel_out, 8'hBB, 17'd200, 11);

        @(negedge clk_write); write_en = 0;

        // addr=201 읽기 확인
        @(negedge clk_read); read_addr = 17'd201;
        @(posedge clk_read); #1;
        check(pixel_out, 8'hAA, 17'd201, 12);

        $display("");

        // ── [6] 연속 읽기 - read_addr 바꿀 때마다 1클럭 뒤에 출력 ──
        $display("[6] 연속 읽기 - read_addr 변경 후 1클럭 레이턴시 재확인");

        // addr=0=0xFF, addr=1=0x10 이미 저장돼 있음 (테스트2에서)
        @(negedge clk_read); read_addr = 17'd0;
        @(posedge clk_read); #1;
        $display("  read_addr=0 → pixel_out=0x%h (기대 0xFF)", pixel_out);

        @(negedge clk_read); read_addr = 17'd1;
        @(posedge clk_read); #1;
        $display("  read_addr=1 → pixel_out=0x%h (기대 0x10)", pixel_out);
        // read_addr 바꾼 직후 클럭 전에는 이전 값이 유지됨을 보여줌

        $display("");

        // ── 최종 결과 ───────────────────────────────────────────────
        $display("============================================");
        $display(" 결과: PASS=%0d / FAIL=%0d / 총=%0d",
                 pass, fail, pass+fail);
        if (fail == 0)
            $display(" 전체 PASS");
        else
            $display(" FAIL 있음 - 위 로그 확인");
        $display("============================================");
        $finish;
    end

endmodule