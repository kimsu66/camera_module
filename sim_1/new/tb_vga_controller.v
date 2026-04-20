`timescale 1ns / 1ps

module tb_vga_controller;

    reg clk = 0;

    wire [9:0] x;
    wire [9:0] y;
    wire       Hsync;
    wire       Vsync;
    wire       active;

    wire [9:0] _h_cnt = DUT.h_cnt;
    wire [9:0] _v_cnt = DUT.v_cnt;

    vga_controller DUT (
        .clk(clk), .x(x), .y(y),
        .Hsync(Hsync), .Vsync(Vsync), .active(active)
    );

    always #20 clk = ~clk;  // 25MHz

    integer pass = 0;
    integer fail = 0;

    task check_bit;
        input       got;
        input       expected;
        input [8*20:1] label;
        begin
            if (got === expected) begin
                $display("  [PASS] %s = %b (기대 %b)", label, got, expected);
                pass = pass + 1;
            end else begin
                $display("  [FAIL] %s = %b (기대 %b) ← 불일치!", label, got, expected);
                fail = fail + 1;
            end
        end
    endtask

    task check_val;
        input [9:0]    got;
        input [9:0]    expected;
        input [8*20:1] label;
        begin
            if (got === expected) begin
                $display("  [PASS] %s = %0d (기대 %0d)", label, got, expected);
                pass = pass + 1;
            end else begin
                $display("  [FAIL] %s = %0d (기대 %0d) ← 불일치!", label, got, expected);
                fail = fail + 1;
            end
        end
    endtask

    // negedge에서 체크 - posedge 업데이트 완료 후 안정된 값
    task wait_h_then_check;
        input [9:0] target;
        begin
            @(negedge clk);
            while (_h_cnt != target) begin
                @(negedge clk);
            end
        end
    endtask

    task wait_v_then_check;
        input [9:0] target;
        begin
            @(negedge clk);
            while (_v_cnt != target) begin
                @(negedge clk);
            end
        end
    endtask

    initial begin
        $display("================================================");
        $display(" tb_vga_controller  (clk=25MHz)");
        $display(" VGA 640x480 @60Hz");
        $display("================================================\n");

        // [1] 초기 상태
        $display("[1] 초기 상태 확인");
        repeat(5) @(negedge clk); #1;
        $display("  h_cnt=%0d v_cnt=%0d Hsync=%b Vsync=%b active=%b",
                 _h_cnt, _v_cnt, Hsync, Vsync, active);
        $display("  기대: Hsync=1 Vsync=1 active=1\n");

        // [2] active 구간
        $display("[2] active 구간 확인");

        wait_h_then_check(10'd0); #1;
        check_bit(active, 1'b1, "active h=0,v=0  ");

        wait_h_then_check(10'd639); #1;
        check_bit(active, 1'b1, "active h=639,v=0");

        wait_h_then_check(10'd640); #1;
        check_bit(active, 1'b0, "active h=640    ");
        $display("");

        // [3] Hsync 구간 (656~751에서 LOW)
        $display("[3] Hsync 구간 확인 (h=656~751에서 LOW)");

        wait_h_then_check(10'd655); #1;
        check_bit(Hsync, 1'b1, "Hsync h=655     ");

        wait_h_then_check(10'd656); #1;
        check_bit(Hsync, 1'b0, "Hsync h=656     ");

        wait_h_then_check(10'd751); #1;
        check_bit(Hsync, 1'b0, "Hsync h=751     ");

        wait_h_then_check(10'd752); #1;
        check_bit(Hsync, 1'b1, "Hsync h=752     ");
        $display("");

        // [4] h_cnt 리셋
        $display("[4] h_cnt=799 -> 0 리셋");
        wait_h_then_check(10'd799); #1;
        $display("  h_cnt=%0d (799 확인)", _h_cnt);
        @(negedge clk); #1;
        check_val(_h_cnt, 10'd0, "h_cnt after 799 ");
        $display("");

        // [5] x, y 1클럭 지연
        $display("[5] x, y 1클럭 지연 확인");
        wait_h_then_check(10'd100); #1;
        $display("  h_cnt=%0d  x=%0d  (x = 이전 클럭 h_cnt)", _h_cnt, x);
        $display("  v_cnt=%0d  y=%0d", _v_cnt, y);
        $display("  기대: x=%0d (h_cnt-1)\n", _h_cnt - 1);

        // [6] Vsync 구간 (v_cnt=490~491에서 LOW)
        $display("[6] Vsync 구간 확인 (v=490~491에서 LOW)");
        $display("    (v_cnt=490까지 대기중...)");

        wait_v_then_check(10'd489);
        wait_h_then_check(10'd799);
        @(negedge clk); #1;  // v=490 진입
        check_bit(Vsync, 1'b0, "Vsync v=490     ");

        wait_v_then_check(10'd491); #1;
        check_bit(Vsync, 1'b0, "Vsync v=491     ");

        wait_v_then_check(10'd492); #1;
        check_bit(Vsync, 1'b1, "Vsync v=492     ");
        $display("");

        // [7] v_cnt 리셋 (1프레임 완료)
        $display("[7] v_cnt=524 -> 0 리셋 (1프레임 완료)");
        $display("    (v_cnt=524까지 대기중...)");
        wait_v_then_check(10'd524);
        wait_h_then_check(10'd799);
        @(negedge clk); #1;
        check_val(_v_cnt, 10'd0, "v_cnt after 524 ");
        $display("");

        $display("================================================");
        $display(" 결과: PASS=%0d / FAIL=%0d / 총=%0d",
                 pass, fail, pass+fail);
        if (fail == 0)
            $display(" 전체 PASS");
        else
            $display(" FAIL 있음 확인 필요");
        $display("================================================");
        $finish;
    end

endmodule