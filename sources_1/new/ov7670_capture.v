`timescale 1ns / 1ps

module ov7670_capture(
    input  wire        pclk,
    input  wire        vsync,
    input  wire        href,
    input  wire  [7:0] d,

    output reg  [15:0] pixel_data,
    output reg         pixel_valid,
    output reg  [16:0] addr
);

    reg byte_sel = 1'b0;
    reg [7:0] low_byte = 8'd0;  // 첫 번째 바이트 = Y (YUYV 포맷의 luma)

    reg [9:0]  x       = 10'd0;
    reg [8:0]  y       = 9'd0;
    reg        vsync_d = 1'b0;

    // YUYV: 첫 번째 바이트 = Y (luma), 두 번째 = U 또는 V (무시)
    wire [7:0] y_val = low_byte;

    // 2x2 평균 필터 - Y 채널만
    reg [7:0] y_prev = 8'd0;

    reg [8:0] y_line [0:319];   // 수평 Y 합 (9-bit, max 510)

    wire [8:0] y_hsum = {1'b0, y_prev} + {1'b0, y_val};

    // 2x2 합 >> 2 = 평균 (10-bit → 상위 8-bit)
    wire [9:0] y_2x2_sum = {1'b0, y_line[x[9:1]]} + {1'b0, y_hsum};
    wire [7:0] y_out     = y_2x2_sum[9:2];

    // grayscale → RGB565 (R:5, G:6, B:5)
    wire [4:0] y_out5 = y_out[7:3];
    wire [5:0] y_out6 = y_out[7:2];

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
        else begin
            if (!byte_sel) begin
                low_byte <= d;  // Y 바이트 캡처
                byte_sel <= 1'b1;
            end else begin
                byte_sel <= 1'b0;  // U/V 바이트는 무시

                if (x[0] == 1'b0) begin
                    // 짝수 픽셀: Y 이전값 저장
                    y_prev <= y_val;
                end else begin
                    // 홀수 픽셀: 수평 쌍 완성
                    if (y[0] == 1'b0) begin
                        // 짝수 행: 수평 Y 합 저장
                        y_line[x[9:1]] <= y_hsum;
                    end else begin
                        // 홀수 행: 2x2 평균 출력 → RGB565 grayscale
                        pixel_data  <= {y_out5, y_out6, y_out5};
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
