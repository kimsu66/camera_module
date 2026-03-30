`timescale 1ns / 1ps

module tb_vga_controller;

    reg clk = 0;
    wire [9:0] x;
    wire [9:0] y;
    wire Hsync;
    wire Vsync;
    wire active;

    // 25MHz -> period 40ns
    always #20 clk = ~clk;

    vga_controller dut (
        .clk(clk),
        .x(x),
        .y(y),
        .Hsync(Hsync),
        .Vsync(Vsync),
        .active(active)
    );

    initial begin
        // 대략 몇 프레임 정도 돌려보기
        #20000000;
        $finish;
    end

endmodule