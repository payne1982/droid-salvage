/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef _UAPI_LINUX_MSM_IRIS2_H
#define _UAPI_LINUX_MSM_IRIS2_H
#include <linux/types.h>
#include <linux/ioctl.h>
#ifndef __KERNEL__
#include <stdbool.h>
#include <stdint.h>
#endif
#ifndef MSMFB_IOCTL_MAGIC
#define MSMFB_IOCTL_MAGIC 'm'
#endif
#if defined(CONFIG_IRIS2_FULL_SUPPORT) || defined(CONFIG_IRIS2P_FULL_SUPPORT) || defined(PXLW_IRIS_COMMON)
struct msmfb_iris_tuning {
	int color_manager;
	int flesh_tone_control;
	int peaking;
	int memc;
	int picture_quality;
	int sensitivity;
	int brightness;
};

struct msmfb_iris_reg_value {
	unsigned int addr;
	unsigned int value;
};

struct msmfb_iris_work_mode {
	unsigned int mode;
	unsigned int enable;
};

struct msmfb_mipi_dsi_cmd {
	__u8 dtype;
	__u8 vc;
#define MSMFB_MIPI_DSI_COMMAND_LAST 1
#define MSMFB_MIPI_DSI_COMMAND_ACK  2
#define MSMFB_MIPI_DSI_COMMAND_HS   4
#define MSMFB_MIPI_DSI_COMMAND_BLLP 8
#define MSMFB_MIPI_DSI_COMMAND_DEBUG 16
	__u16 flags;
	__u16 length;
	__u8 *payload;
	__u8 response[16];
};

#if defined(CONFIG_IRIS2P_FULL_SUPPORT) || defined(PXLW_IRIS2P)
enum {
	MSMFB_IRIS_I2C_READ = 0x01,
	MSMFB_IRIS_I2C_WRITE = 0X02,
};

struct msmfd_iris_i2c_cmd {
#define MAX_ADDR_COMP_LEN   40
	__u8 type;
	int addr_comp_len;
	struct addr_val{
		__u32 addr;
		__u32 data;
	} addr_comp[MAX_ADDR_COMP_LEN];
};

struct msmfb_iris_operate_value {
	unsigned int type;
	unsigned int count;
	void *values;
};
#else
struct msmfb_iris_configure_value {
	unsigned int type;
	unsigned int value;
};

struct msmfb_iris_configure_ex_value {
	unsigned int type;
	unsigned int count;
	int32_t *values;
};
#endif

struct msmfb_iris_frc_path {
	int bit_index;
	int enable;
};

struct iris_nrv_meta {
	uint8_t nrvEnable;          // 1: eanble NRV, 0: disable NRV
	uint8_t backgroundColor;    // TBD
	// Catpure rectangle
	uint16_t captureLeft;
	uint16_t captureRight;
	uint16_t captureTop;
	uint16_t captureBottom;
	// Display rectangle
	uint16_t displayLeft;
	uint16_t displayRight;
	uint16_t displayTop;
	uint16_t displayBottom;
	// scale parameters, TBD
};

struct iris_meta {
	uint32_t op;
	uint8_t  new_frame;
	uint8_t  restart;
	uint32_t flags;
	uint32_t video_ts;
	uint32_t sys_ts;
	uint32_t iris_info1;  // information from server
	uint32_t iris_info2;  // information from server
	uint8_t  vid;
	uint32_t te_period;
	uint32_t content_period;
	uint32_t content_period_frac;
	uint32_t vs_period;
	uint32_t vs_period_frac;
	uint8_t  motion;
	uint8_t  jitter;
	struct iris_nrv_meta nrv;
	uint8_t  repeat;	// 0: new frame 1: force repeat 2: capture disable
};

struct iris_available_mode {
	uint8_t pt_available;
	uint8_t prefer_mode;
	uint8_t bypass_available;
	uint8_t kickoff60_request;
	uint8_t last_frame_repeat_cnt;
	uint8_t pt_threshold_low;	// RFB->PT condition: fps < pt_threshold_low || fps > pt_threshold_high
	uint8_t rfb_threshold_low;	// PT->RFB condition: fps > rfb_threshold_low && fps < rfb_threshold_high
	uint8_t rfb_threshold_high;
	uint8_t pt_threshold_high;
	uint32_t dsi_mode_in_rfb;	// dsi mode in rfb, 0: DSI_VIDEO_MODE, 1: DSI_CMD_MODE
	uint32_t dsi_mode_in_ptl;	// dsi mode in pt low
	uint32_t dsi_mode_in_pth;	// dsi mode in pt high
};

#define MDP_IRIS_OP_NEW_FRAME	0x1
#define MDP_IRIS_OP_RESTART     0x2
#define MDP_IRIS_OP_VTS         0x4
#define MDP_IRIS_OP_STS         0x8
#define MDP_IRIS_OP_VID         0x10
#define MDP_IRIS_OP_TE          0x20
#define MDP_IRIS_OP_CP          0x40
#define MDP_IRIS_OP_MOTION      0x80
#define MDP_IRIS_OP_JITTER      0x100
#define MDP_IRIS_OP_NRV         0x200
#define MDP_IRIS_OP_FLG         0x400
#define MDP_IRIS_OP_RPT         0x800
#define MDP_IRIS_OP_IF1         0x1000
#define MDP_IRIS_OP_IF2         0x2000

enum iris_config_type {
	IRIS_PEAKING = 0,            // MB3[3:0] | [24]
	IRIS_SHARPNESS = 1,          // MB3[7:4] | [25]
	IRIS_MEMC_DEMO = 2,          // MB3[9:8] | [26]
	IRIS_PEAKING_DEMO = 3,       // MB3[11:10] | [27]
	IRIS_GAMMA = 4,              // MB3[13:12] | [28]
	IRIS_MEMC_LEVEL = 5,         // MB3[15:14] | [29]
	IRIS_CONTRAST = 6,           // MB3[23:16] | [30]
	IRIS_BRIGHTNESS = 7,         // MB5[14:8]
	IRIS_EXTERNAL_PWM = 8,       // MB5[15]
	IRIS_DBC_QUALITY = 9,        // MB5[19:16]
	IRIS_DLV_SENSITIVITY = 10,   // MB5[31:20]
	IRIS_DBC_CONFIG = 11,        // MB5
	IRIS_PQ_CONFIG = 12,         // MB3
	IRIS_MEMC_ENABLE = 13,       // 0: OFF, 1: ON
	IRIS_MEMC_OPTION = 14,       // 0: PANEL_RESOLUTION, 1: NATIVE_RESOLUTION, 2: LOW_POWER
	IRIS_LPMEMC_CONFIG = 15,
	IRIS_DCE_LEVEL = 16,         // MB5[7:4]
	IRIS_USER_DEMO_WND = 17,
	IRIS_MEMC_ACTIVE = 18,
	IRIS_WHITE_LIST_ADD = 19,    // add white list
	IRIS_WHITE_LIST_RST = 20,    // reset white list
	IRIS_LAYER_SIZE = 21,        // layer size
	IRIS_BLACK_BORDER = 22,      // 1: has black border, 0: no black border
	IRIS_CINEMA_MODE = 23,       // MB3[31] | [25]
	IRIS_BLACK_LIST_ADD = 24,    // add black list
	IRIS_BLACK_LIST_RST = 25,    // reset black list
	IRIS_COLOR_ADJUST = 26,
	IRIS_TRUE_CUT_CAP = 27,      // read only: true-cut capability
	IRIS_TRUE_CUT_DET = 28,      // read only true-cut video detected
	IRIS_PT_ENABLE = 29,
	IRIS_BYPASS_ENABLE = 30,
	IRIS_LCE_SETTING = 31,
	IRIS_CM_SETTING = 32,
	IRIS_CHIP_VERSION = 33,      // 0x0 : IRIS2, 0x1 : IRIS2-plus
	IRIS_LUX_VALUE = 34,
	IRIS_CCT_VALUE = 35,
	IRIS_READING_MODE = 36,

	// For config only used in system, start from 100 if possible.
	IRIS_SEND_FRAME = 100,
	IRIS_OSD_PATTERN_SHOW = 101,
	IRIS_DBG_TARGET_PI_REGADDR_SET = 102,
	IRIS_DBG_TARGET_REGADDR_VALUE_GET = 103,
	IRIS_MEMC_ENABLE_FOR_ASUS_CAMERA = 104,
	IRIS_DBG_TARGET_REGADDR_VALUE_SET = 105,
	IRIS_APP_FILTER = 111,
	IRIS_CONFIG_TYPE_MAX
};

#if defined(CONFIG_IRIS2_FULL_SUPPORT) || defined(PXLW_IRIS2)
#define MSMFB_IRIS_TUNING _IOW(MSMFB_IOCTL_MAGIC, 200, struct msmfb_iris_tuning)
#define MSMFB_IRIS_WRITE_REG _IOW(MSMFB_IOCTL_MAGIC, 201, struct msmfb_iris_reg_value)
#define MSMFB_IRIS_NOTIFY_SCENARIO _IOW(MSMFB_IOCTL_MAGIC, 202, int)
#define MSMFB_IRIS_NOTIFY_WORK_MODE _IOW(MSMFB_IOCTL_MAGIC, 203, struct msmfb_iris_work_mode)
#define MSMFB_IRIS_FRC_SWITCH _IOW(MSMFB_IOCTL_MAGIC, 204, int)
#define MSMFB_MIPI_DSI_COMMAND _IOWR(MSMFB_IOCTL_MAGIC, 205, struct msmfb_mipi_dsi_cmd)
#define MSMFB_IRIS_CONFIGURE _IOW(MSMFB_IOCTL_MAGIC, 206, struct msmfb_iris_configure_value)
#define MSMFB_IRIS_CONFIGURE_EX _IOW(MSMFB_IOCTL_MAGIC, 207, struct msmfb_iris_configure_ex_value)
#define MSMFB_IRIS_CONFIGURE_GET _IOW(MSMFB_IOCTL_MAGIC, 208, struct msmfb_iris_configure_value)
#define MSMFB_IRIS_NOTIFY_VIDEO_FRAME_RATE _IOW(MSMFB_IOCTL_MAGIC, 209, unsigned int)
#define MSMFB_IRIS_SET_META _IOW(MSMFB_IOCTL_MAGIC, 210, struct iris_meta)
#define MSMFB_IRIS_SET_MODE _IOW(MSMFB_IOCTL_MAGIC, 211, unsigned int)
#define MSMFB_IRIS_GET_MODE _IOW(MSMFB_IOCTL_MAGIC, 212, unsigned int)
#define MSMFB_IRIS_FRC_PATH_UPDATE _IOW(MSMFB_IOCTL_MAGIC, 213, struct msmfb_iris_frc_path)
#define MSMFB_IRIS_SET_ROTATION _IOW(MSMFB_IOCTL_MAGIC, 214, bool)
#endif
#if defined(CONFIG_IRIS2P_FULL_SUPPORT) || defined(PXLW_IRIS2P)
#define MSMFB_IRIS_SET_META _IOW(MSMFB_IOCTL_MAGIC, 200, struct iris_meta)
#define MSMFB_IRIS_OPERATE_CONF _IOW(MSMFB_IOCTL_MAGIC, 201, struct msmfb_iris_operate_value)
#define MSMFB_IRIS_OPERATE_MODE _IOW(MSMFB_IOCTL_MAGIC, 202, struct msmfb_iris_operate_value)
#define MSMFB_IRIS_OPERATE_TOOL _IOW(MSMFB_IOCTL_MAGIC, 203, struct msmfb_iris_operate_value)
#endif
#if defined(CONFIG_IRIS2_DRC_SUPPORT) || defined(CONFIG_IRIS2P_DRC_SUPPORT) || defined(PXLW_IRIS2_DRC) || defined(PXLW_IRIS2P_DRC)
#define MSMFB_IRIS_GET_FRCTIMING _IOW(MSMFB_IOCTL_MAGIC, 215, unsigned int)
#define MSMFB_IRIS_SET_DRC_SIZE _IOW(MSMFB_IOCTL_MAGIC, 216, unsigned int)
#endif

#define IRIS_MODE_RFB                   0x0
#define IRIS_MODE_FRC_PREPARE           0x1
#define IRIS_MODE_FRC_PREPARE_DONE      0x2
#define IRIS_MODE_FRC                   0x3
#define IRIS_MODE_FRC_CANCEL            0x4
#define IRIS_MODE_FRC_PREPARE_RFB       0x5
#define IRIS_MODE_FRC_PREPARE_TIMEOUT   0x6
#define IRIS_MODE_RFB2FRC               0x7
#define IRIS_MODE_RFB_PREPARE           0x8
#define IRIS_MODE_RFB_PREPARE_DONE      0x9
#define IRIS_MODE_RFB_PREPARE_TIMEOUT   0xa
#define IRIS_MODE_FRC2RFB               0xb
#define IRIS_MODE_PT_PREPARE            0xc
#define IRIS_MODE_PT_PREPARE_DONE       0xd
#define IRIS_MODE_PT_PREPARE_TIMEOUT    0xe
#define IRIS_MODE_RFB2PT                0xf
#define IRIS_MODE_PT2RFB                0x10
#define IRIS_MODE_PT                    0x11
#define IRIS_MODE_KICKOFF60_ENABLE      0x12
#define IRIS_MODE_KICKOFF60_DISABLE     0x13
#define IRIS_MODE_PT2BYPASS             0x14
#define IRIS_MODE_BYPASS                0x15
#define IRIS_MODE_BYPASS2PT             0x16
#define IRIS_MODE_PTLOW_PREPARE         0x17
#define IRIS_MODE_DSI_SWITCH_2PT     	0x18    // dsi mode switch during RFB->PT
#define IRIS_MODE_DSI_SWITCH_2RFB    	0x19    // dsi mode switch during PT->RFB
#define IRIS_MODE_INITING		0xff
#define IRIS_MODE_OFF			0xf0

#if defined(CONFIG_IRIS2P_FULL_SUPPORT) || defined(PXLW_IRIS2P)
#define IRIS_PT_CAP_CIN_VOUT            0x1
#define IRIS_PT_CAP_VIN_VOUT            0x2
#define IRIS_PT_CAP_CIN_COUT            0x4

enum iris_oprt_type {
	IRIS_OPRT_CONFIGURE = 1,
	IRIS_OPRT_CONFIGURE_NEW,
	IRIS_OPRT_ROTATION_SET,
	IRIS_OPRT_DYNAMIC_FPS_SET,
	IRIS_OPRT_VIDEO_FRAME_RATE_SET,
	IRIS_OPRT_CONFIGURE_NEW_GET,
	IRIS_OPRT_TOOL_DSI,
	IRIS_OPRT_TOOL_I2C,
	IRIS_OPRT_MODE_SET,
	IRIS_OPRT_MODE_GET,
	IRIS_OPRT_DPORT_WRITEBACK_SKIP,
	IRIS_OPRT_MIPITX_MODESWITCH,
	IRIS_OPRT_GET_FRCTIMING,
	IRIS_OPRT_SET_DRC_SIZE,
	IRIS_OPRT_GET_AVAILABLE_MODE,
};

enum iris_memc_option {
	IRIS_MEMC_PANEL_RESOLUTION,
	IRIS_MEMC_NATIVE_RESOLUTION,
	IRIS_MEMC_LOW_POWER,
};
#endif
#endif // CONFIG_IRIS2_FULL_SUPPORT || CONFIG_IRIS2P_FULL_SUPPORT || PXLW_IRIS_COMMON
#endif
