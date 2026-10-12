# initramfs-ps4
 Custom Initramfs for PS4. (based on better-initramfs)
# Features:
1. internal and external in one
2. fixed automatic script
3. auto eject disc (incase it breaks internal)
4. has ext4 formatting capability
5. uses distro.tar.xz instead of psxitarch.tar.xz
6. edid fix

# How to run:
On a linux host, run `./bake.sh`, It will produce an `initramfs.cpio.gz` file. (vulkan will be broken this way, as local builds dont have firmware)

The PS4 loader must add `/key/eap_hdd_key.bin` to the initramfs. The internal drive can not be opened without it.

...Or download from releases https://github.com/GattoDev-debug/initramfs-ps4/releases/latest
