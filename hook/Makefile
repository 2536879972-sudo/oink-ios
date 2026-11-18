# Theos 工程根 Makefile
# 放在 ios-kit/hook/ 下（与 tweak/ 同级时用 aggregate），单 tweak 时直接放根即可

export THEOS_DEVICE_IP = 192.168.1.100   # 越狱机 IP，改成你的
export THEOS_DEVICE_PORT = 22

TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
