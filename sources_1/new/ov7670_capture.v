`timescale 1ns / 1ps

module ov7670_capture(
    input  wire       pclk,
    input  wire       vsync,
    input  wire       href,
    input  wire [7:0] d,

    output reg [7:0]  pixel_data,
    output reg        pixel_valid,
    output reg [16:0] addr
);

    reg byte_sel = 1'b0;
    reg [7:0] high_byte = 8'd0;

    reg [9:0]  x       = 10'd0;
    reg [8:0]  y       = 9'd0;
    reg        vsync_d = 1'b0;

    // byte 순서: 첫 번째 바이트 = low byte (GGGBBBBB)
    //           두 번째 바이트 = high byte (RRRRRGGG)
    wire [4:0] r5 = d[7:3];
    wire [5:0] g6 = {d[2:0], high_byte[7:5]};
    wire [4:0] b5 = high_byte[4:0];

    // 5/6-bit → 8-bit 확장 (MSB 반복)
    wire [7:0] r8 = {r5, r5[4:2]};
    wire [7:0] g8 = {g6, g6[5:4]};
    wire [7:0] b8 = {b5, b5[4:2]};

    // ITU-R BT.601 가중 그레이스케일: 0.299R + 0.587G + 0.114B ≈ R*77 + G*150 + B*29 (÷256)
    wire [15:0] r_w = r8 * 8'd77;
    wire [15:0] g_w = g8 * 8'd150;
    wire [15:0] b_w = b8 * 8'd29;
    wire  [7:0] gray8 = (r_w + g_w + b_w) >> 8;

    // 2x2 안티앨리어싱 필터
    reg [7:0] gray_prev = 8'd0;      // 직전 픽셀 gray (수평 누산용)
    reg [8:0] line_buf [0:319];      // 이전 행의 수평 합 (9-bit x 320)

    wire [8:0] h_sum = {1'b0, gray_prev} + {1'b0, gray8};

    always @(posedge pclk) begin
        pixel_valid <= 1'b0;
        vsync_d     <= vsync;

        if (vsync && !vsync_d) begin
            x        <= 10'd0;
            y        <= 9'd0;
            byte_sel <= 1'b0;
        end
        else if (!href) begin
            byte_sel <= 1'b0;   // 라인마다 byte 정렬 리셋
        end
        else begin  // href active
            if (!byte_sel) begin
                high_byte <= d;
                byte_sel  <= 1'b1;
            end else begin
                byte_sel <= 1'b0;

                if (x[0] == 1'b0) begin
                    // 짝수 픽셀: gray 저장
                    gray_prev <= gray8;
                end else begin
                    // 홀수 픽셀: 수평 2픽셀 합 완성
                    if (y[0] == 1'b0) begin
                        // 짝수 행: line_buf에 저장
                        line_buf[x[9:1]] <= h_sum;
                    end else begin
                        // 홀수 행: 2x2 평균 출력 (÷4)
                        pixel_data  <= ({1'b0, line_buf[x[9:1]]} + {1'b0, h_sum}) >> 2;
                        pixel_valid <= 1'b1;
                        addr <= ({1'b0, y[8:1], 8'b0}
                               + {3'b0, y[8:1], 6'b0}
                               + {8'b0, x[9:1]});
                    end
                end

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
