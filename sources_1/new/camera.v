`timescale 1ns / 1ps

module top(
    input  wire       clk,

    input  wire [7:0] cam_d,
    input  wire       cam_vsync,
    input  wire       cam_pclk,
    input  wire       cam_href,

    output wire       cam_scl,
    inout  wire       cam_sda,
    output wire       cam_rst,
    output wire       cam_xclk,
    output wire       cam_pwdn,

    output wire [2:0] led,

    output wire [3:0] vgaRed,
    output wire [3:0] vgaGreen,
    output wire [3:0] vgaBlue,
    output wire       Hsync,
    output wire       Vsync
);

    // =====================
    // Camera basic control
    // =====================
    assign cam_rst  = 1'b1;   // reset inactive
    assign cam_pwdn = 1'b0;   // power-down off

    // =========================
    // 100MHz -> 25MHz
    // camera xclk + VGA pixel clock
    // =========================
    reg [1:0] div4_reg = 2'd0;
    always @(posedge clk) begin
        div4_reg <= div4_reg + 2'd1;
    end
    wire clk_25mhz;
    assign clk_25mhz = div4_reg[1];   // 25MHz for VGA + cam_xclk
    assign cam_xclk  = clk_25mhz;

    // =====================
    // OV7670 init
    // =====================
    wire init_done;

    ov7670_init u_init (
        .clk      (clk),
        .resetn   (1'b1),
        .scl      (cam_scl),
        .sda      (cam_sda),
        .done     (init_done)   // init 완료 표시
    );

    // =========================
    // OV7670 capture
    // =========================
    wire [15:0] pixel_data;
    wire        pixel_valid;
    wire [14:0] write_addr;

    ov7670_capture capture(
        .pclk(cam_pclk),
        .vsync(cam_vsync),
        .href(cam_href),
        .d(cam_d),
        .pixel_data(pixel_data),
        .pixel_valid(pixel_valid),
        .addr(write_addr)
    );

    // =========================
    // VGA timing generator
    // BUG FIX: was missing entirely!
    // =========================
    wire [9:0] vga_x;
    wire [9:0] vga_y;
    wire       vga_active;
    
    vga_controller u_vga (
        .clk    (clk_25mhz),
        .x      (vga_x),
        .y      (vga_y),
        .Hsync  (Hsync),
        .Vsync  (Vsync),
        .active (vga_active)
    );
    
    // =========================
    // Frame buffer read address
    // 160x120 image -> 640x480 by 4x scaling
    // =========================
    wire [7:0]  fb_x;
    wire [6:0]  fb_y;
    wire [14:0] read_addr;
    wire [15:0] pixel_out;

    assign fb_x     = vga_x[9:2];              // /4
    assign fb_y     = vga_y[9:2];              // /4  (use [9:2] for 120 rows)
    assign read_addr = {fb_y, 7'd0} + {fb_y, 5'd0} + fb_x;
    // = fb_y*128 + fb_y*32 + fb_x = fb_y*160 + fb_x
    // (avoids multiplication in synthesizer)
 
    // =========================
    // Frame buffer (dual-port BRAM)
    // BUG FIX: only ONE instance, correct clock for read
    // =========================
    frame_buffer u_fb (
        .clk_write (cam_pclk),
        .write_en  (pixel_valid),
        .write_addr(write_addr),
        .pixel_in  (pixel_data),
 
        .clk_read  (clk_25mhz),   // same domain as VGA
        .read_addr (read_addr),
        .pixel_out (pixel_out)
    );

    // =========================
    // VGA color output
    // RGB565 -> RGB444
    // =========================
    assign vgaRed   = vga_active ? pixel_out[15:12] : 4'b0000;
    assign vgaGreen = vga_active ? pixel_out[10:7]  : 4'b0000;
    assign vgaBlue  = vga_active ? pixel_out[4:1]   : 4'b0000;

    // =========================
    // LEDs
    // =========================
    assign led[0] = init_done;
    assign led[1] = cam_vsync;
    assign led[2] = cam_href;


endmodule