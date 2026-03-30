`timescale 1ns / 1ps

module ov7670_capture(
    input  wire       pclk,
    input  wire       vsync,
    input  wire       href,
    input  wire [7:0] d,

    output reg [15:0] pixel_data,
    output reg        pixel_valid,
    output reg [14:0] addr
);

    reg byte_sel = 1'b0;
    reg [7:0] high_byte = 8'd0;

    reg [9:0]  x         = 10'd0; // 0~639
    reg [8:0]  y         = 9'd0;  // 0~479
    reg        vsync_d   = 1'b0;


    always @(posedge pclk) begin
        pixel_valid <= 1'b0;
        vsync_d     <= vsync;
 
        // vsync 상승 엣지: 새 프레임 시작
        if (vsync && !vsync_d) begin
            x        <= 10'd0;
            y        <= 9'd0;
            byte_sel <= 1'b0;
        end
        else if (href) begin
            // byte_sel=0: 상위 바이트, byte_sel=1: 하위 바이트
            if (!byte_sel) begin
                high_byte <= d;
                byte_sel  <= 1'b1;
            end else begin
                byte_sel <= 1'b0;
 
                // x, y 둘 다 4의 배수일 때만 저장
                if (x[1:0] == 2'b00 && y[1:0] == 2'b00) begin
                    pixel_data  <= {high_byte, d};
                    pixel_valid <= 1'b1;
                    // addr = (y/4)*160 + (x/4)
                    // y[8:2] = y/4 (0~119), x[9:2] = x/4 (0~159)
                    // (y/4)*160 = (y/4)*128 + (y/4)*32
                    addr <= ({y[8:2], 7'd0} + {y[8:2], 5'd0} + x[9:2]);
                end
 
                // x 카운터: 0~639
                if (x == 10'd639) begin
                    x <= 10'd0;
                    if (y < 9'd479)
                        y <= y + 9'd1;
                end else begin
                    x <= x + 10'd1;
                end
            end
        end
    end

endmodule