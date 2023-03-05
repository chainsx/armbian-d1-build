#!/bin/bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:

# compilation_prepare

compilation_prepare()
{

	# Packaging patch for modern kernels should be one for all.
	# Currently we have it per kernel family since we can't have one
	# Maintaining one from central location starting with 5.3+
	# Temporally set for new "default->legacy,next->current" family naming

	if linux-version compare "${version}" ge 5.17.3; then

		if test -d ${kerneldir}/debian
		then
			rm -rf ${kerneldir}/debian/*
		fi
		sed -i -e '
			s/^KBUILD_IMAGE	:= \$(boot)\/Image\.gz$/KBUILD_IMAGE	:= \$(boot)\/Image/
		' ${kerneldir}/arch/arm64/Makefile

		sed -i -e '
			s/^KBUILD_IMAGE	:= \$(boot)\/Image\.gz$/KBUILD_IMAGE	:= \$(boot)\/Image/
		' ${kerneldir}/arch/riscv/Makefile

		rm -f ${kerneldir}/scripts/package/{builddeb,mkdebian}

		cp ${SRC}/packages/armbian/builddeb ${kerneldir}/scripts/package/builddeb
		cp ${SRC}/packages/armbian/mkdebian ${kerneldir}/scripts/package/mkdebian

		chmod 755 ${kerneldir}/scripts/package/{builddeb,mkdebian}
	fi

	# After the patches have been applied,
	# check and add debian package compression if required.
	#
	if [ "$(awk '/dpkg --build/{print $1}' $kerneldir/scripts/package/builddeb)" == "dpkg" ];then
		sed -i -e '
			s/dpkg --build/dpkg-deb \${KDEB_COMPRESS:+-Z\$KDEB_COMPRESS} --build/
			' "$kerneldir"/scripts/package/builddeb
	fi

	#
	# mac80211 wireless driver injection features from Kali Linux
	#

	if linux-version compare "${version}" ge 5.17.3 && [ $EXTRAWIFI == yes ]; then

		display_alert "Adding" "Wireless package injections for mac80211 compatible chipsets" "info"
		process_patch_file "${SRC}/patch/misc/kali-wifi-injection-1-v5.9-post.patch" "applying"
		process_patch_file "${SRC}/patch/misc/kali-wifi-injection-2.patch" "applying"
		process_patch_file "${SRC}/patch/misc/kali-wifi-injection-3.patch" "applying"

	fi

	# AUFS - advanced multi layered unification filesystem for Kernel > 5.17
	#
	# Older versions have AUFS support with a patch

	if linux-version compare "${version}" gt 5.17.3 && linux-version compare "${version}" lt 5.19 && [ "$AUFS" == yes ]; then

		# attach to specifics tag or branch
		local aufstag
		aufstag=$(echo "${version}" | cut -f 1-2 -d ".")

		# manual overrides
		if linux-version compare "${version}" ge 5.17.3 && linux-version compare "${version}" le 5.18 ; then aufstag="5.17.3"; fi

		# check if Mr. Okajima already made a branch for this version
		improved_git ls-remote --exit-code --heads $GITHUB_SOURCE/sfjro/aufs5-standalone "aufs${aufstag}" >/dev/null

		if [ "$?" -ne "0" ]; then
			# then use rc branch
			aufstag="5.x-rcN"
			improved_git ls-remote --exit-code --heads $GITHUB_SOURCE/sfjro/aufs5-standalone "aufs${aufstag}" >/dev/null
		fi

		if [ "$?" -eq "0" ]; then

			display_alert "Adding" "AUFS ${aufstag}" "info"
			local aufsver="branch:aufs${aufstag}"
			fetch_from_repo "$GITHUB_SOURCE/sfjro/aufs5-standalone" "aufs5" "branch:${aufsver}" "yes"
			cd "$kerneldir" || exit
			process_patch_file "${SRC}/cache/sources/aufs5/${aufsver#*:}/aufs5-kbuild.patch" "applying"
			process_patch_file "${SRC}/cache/sources/aufs5/${aufsver#*:}/aufs5-base.patch" "applying"
			process_patch_file "${SRC}/cache/sources/aufs5/${aufsver#*:}/aufs5-mmap.patch" "applying"
			process_patch_file "${SRC}/cache/sources/aufs5/${aufsver#*:}/aufs5-standalone.patch" "applying"
			cp -R "${SRC}/cache/sources/aufs5/${aufsver#*:}"/{Documentation,fs} .
			cp "${SRC}/cache/sources/aufs5/${aufsver#*:}"/include/uapi/linux/aufs_type.h include/uapi/linux/

		fi
	fi

	# Updated USB network drivers for RTL8152/RTL8153 based dongles that also support 2.5Gbs variants

	if linux-version compare "${version}" ge 5.17.3 && linux-version compare "${version}" le 5.19 && [ $EXTRAWIFI == yes ]; then

		# attach to specifics tag or branch
		local rtl8152ver="branch:master"

		display_alert "Adding" "Drivers for 2.5Gb RTL8152/RTL8153 USB dongles ${rtl8152ver}" "info"
		fetch_from_repo "$GITHUB_SOURCE/igorpecovnik/realtek-r8152-linux" "rtl8152" "${rtl8152ver}" "yes"
		cp -R "${SRC}/cache/sources/rtl8152/${rtl8152ver#*:}"/{r8152.c,compatibility.h} \
		"$kerneldir/drivers/net/usb/"

	fi

	# Wireless drivers for Realtek 8189ES chipsets

	if linux-version compare "${version}" ge 5.17.3 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8189esver="branch:master"

		display_alert "Adding" "Wireless drivers for Realtek 8189ES chipsets ${rtl8189esver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/jwrdegoede/rtl8189ES_linux" "rtl8189es" "${rtl8189esver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8189es"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8189es/"
		cp -R "${SRC}/cache/sources/rtl8189es/${rtl8189esver#*:}"/{core,hal,include,os_dep,platform} \
		"$kerneldir/drivers/net/wireless/rtl8189es"

		# Makefile
		cp "${SRC}/cache/sources/rtl8189es/${rtl8189esver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl8189es/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8189es/${rtl8189esver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8189es/${rtl8189esver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8189es/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8189ES) += rtl8189es/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8189es\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

	fi

	# Wireless drivers for Realtek 8189FS chipsets

	if linux-version compare "${version}" ge 5.17.3 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8189fsver="branch:rtl8189fs"

		display_alert "Adding" "Wireless drivers for Realtek 8189FS chipsets ${rtl8189fsver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/jwrdegoede/rtl8189ES_linux" "rtl8189fs" "${rtl8189fsver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8189fs"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8189fs/"
		cp -R "${SRC}/cache/sources/rtl8189fs/${rtl8189fsver#*:}"/{core,hal,include,os_dep,platform} \
		"$kerneldir/drivers/net/wireless/rtl8189fs"

		# Makefile
		cp "${SRC}/cache/sources/rtl8189fs/${rtl8189fsver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl8189fs/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8189fs/${rtl8189fsver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8189fs/${rtl8189fsver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8189fs/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8189FS) += rtl8189fs/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8189fs\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

	fi

	# Wireless drivers for Realtek 8192EU chipsets

	if linux-version compare "${version}" ge 5.17.3 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8192euver="branch:realtek-4.4.x"

		display_alert "Adding" "Wireless drivers for Realtek 8192EU chipsets ${rtl8192euver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/Mange/rtl8192eu-linux-driver" "rtl8192eu" "${rtl8192euver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8192eu"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8192eu/"
		cp -R "${SRC}/cache/sources/rtl8192eu/${rtl8192euver#*:}"/{core,hal,include,os_dep,platform} \
		"$kerneldir/drivers/net/wireless/rtl8192eu"

		# Makefile
		cp "${SRC}/cache/sources/rtl8192eu/${rtl8192euver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl8192eu/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8192eu/${rtl8192euver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8192eu/${rtl8192euver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8192eu/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8192EU) += rtl8192eu/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8192eu\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

	fi

	# Wireless drivers for Realtek 8811, 8812, 8814 and 8821 chipsets

	if linux-version compare "${version}" ge 5.17.3 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8812auver="branch:v5.6.4.2"

		display_alert "Adding" "Wireless drivers for Realtek 8811, 8812, 8814 and 8821 chipsets ${rtl8812auver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/aircrack-ng/rtl8812au" "rtl8812au" "${rtl8812auver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8812au"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8812au/"
		cp -R "${SRC}/cache/sources/rtl8812au/${rtl8812auver#*:}"/{core,hal,include,os_dep,platform} \
		"$kerneldir/drivers/net/wireless/rtl8812au"

		# Makefile
		cp "${SRC}/cache/sources/rtl8812au/${rtl8812auver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl8812au/Makefile"

		# Kconfig
		cp "${SRC}/cache/sources/rtl8812au/${rtl8812auver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8812au/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_88XXAU) += rtl8812au/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8812au\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

	fi

	# Wireless drivers for Xradio XR819 chipsets
	if linux-version compare "${version}" ge 5.17.3 && [[ "$LINUXFAMILY" == sunxi* ]] && [[ "$EXTRAWIFI" == yes ]]; then

		display_alert "Adding" "Wireless drivers for Xradio XR819 chipsets" "info"

		fetch_from_repo "$GITHUB_SOURCE/karabek/xradio" "xradio" "branch:master" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/xradio"
		mkdir -p "$kerneldir/drivers/net/wireless/xradio/"
		cp "${SRC}"/cache/sources/xradio/master/*.{h,c} \
		"$kerneldir/drivers/net/wireless/xradio/"

		# Makefile
		cp "${SRC}/cache/sources/xradio/master/Makefile" \
		"$kerneldir/drivers/net/wireless/xradio/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/xradio/master/Kconfig"
		cp "${SRC}/cache/sources/xradio/master/Kconfig" \
		"$kerneldir/drivers/net/wireless/xradio/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_WLAN_VENDOR_XRADIO) += xradio/" \
		>> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/xradio\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

		# add support for K5.13+
                process_patch_file "${SRC}/patch/misc/wireless-xradio-5.13.patch" "applying"

	fi

	# Wireless drivers for Realtek RTL8811CU and RTL8821C chipsets

	if linux-version compare "${version}" ge 5.17.3 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8811cuver="commit:8c2226a74ae718439d56248bd2e44ccf717086d5"

		display_alert "Adding" "Wireless drivers for Realtek RTL8811CU and RTL8821C chipsets ${rtl8811cuver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/brektrou/rtl8821CU" "rtl8811cu" "${rtl8811cuver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8811cu"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8811cu/"
		cp -R "${SRC}/cache/sources/rtl8811cu/${rtl8811cuver#*:}"/{core,hal,include,os_dep,platform,rtl8821c.mk} \
		"$kerneldir/drivers/net/wireless/rtl8811cu"

		# Makefile
		cp "${SRC}/cache/sources/rtl8811cu/${rtl8811cuver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl8811cu/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8811cu/${rtl8811cuver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8811cu/${rtl8811cuver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8811cu/Kconfig"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
		"$kerneldir/drivers/net/wireless/rtl8811cu/Makefile"

		# Address ARM related bug $GITHUB_SOURCE/aircrack-ng/rtl8812au/issues/233
		sed -i "s/^CONFIG_MP_VHT_HW_TX_MODE.*/CONFIG_MP_VHT_HW_TX_MODE = n/" \
		"$kerneldir/drivers/net/wireless/rtl8811cu/Makefile"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8821CU) += rtl8811cu/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8811cu\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

		# add support for 5.18.y
		process_patch_file "${SRC}/patch/misc/wireless-rtl8821cu.patch" "applying"

	fi

	# Wireless drivers for Realtek 8188EU 8188EUS and 8188ETV chipsets

	if linux-version compare "${version}" ge 5.17.3 \
		&& linux-version compare "${version}" lt 5.19.2 \
		&& [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8188euver="branch:v5.7.6.1"

		display_alert "Adding" "Wireless drivers for Realtek 8188EU 8188EUS and 8188ETV chipsets ${rtl8188euver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/aircrack-ng/rtl8188eus" "rtl8188eu" "${rtl8188euver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8188eu"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8188eu/"
		cp -R "${SRC}/cache/sources/rtl8188eu/${rtl8188euver#*:}"/{core,hal,include,os_dep,platform} \
		"$kerneldir/drivers/net/wireless/rtl8188eu"

		# Makefile
		cp "${SRC}/cache/sources/rtl8188eu/${rtl8188euver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl8188eu/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8188eu/${rtl8188euver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8188eu/${rtl8188euver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8188eu/Kconfig"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
		"$kerneldir/drivers/net/wireless/rtl8188eu/Makefile"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8188EU) += rtl8188eu/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8188eu\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

		process_patch_file "${SRC}/patch/misc/wireless-rtl8188eu.patch" "applying"

		# add support for K5.12+
		process_patch_file "${SRC}/patch/misc/wireless-realtek-8188eu-5.12.patch" "applying"

	fi

	# Wireless drivers for Realtek 88x2bu chipsets

	if linux-version compare "${version}" ge 5.17.3 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl88x2buver="branch:5.8.7.1_35809.20191129_COEX20191120-7777"

		display_alert "Adding" "Wireless drivers for Realtek 88x2bu chipsets ${rtl88x2buver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/cilynx/rtl88x2bu" "rtl88x2bu" "${rtl88x2buver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl88x2bu"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl88x2bu/"
		cp -R "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}"/{core,hal,include,os_dep,platform,halmac.mk,rtl8822b.mk} \
		"$kerneldir/drivers/net/wireless/rtl88x2bu"

		# Makefile
		cp "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl88x2bu/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl88x2bu/Kconfig"

		# Adjust path
		sed -i 's/include $(src)\/rtl8822b.mk /include $(TopDIR)\/drivers\/net\/wireless\/rtl88x2bu\/rtl8822b.mk/' \
		"$kerneldir/drivers/net/wireless/rtl88x2bu/Makefile"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8822BU) += rtl88x2bu/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl88x2bu\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

	fi

	# Wireless drivers for Realtek 88x2cs chipsets

	if linux-version compare "${version}" ge 5.17.3 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl88x2csver="branch:tune_for_jethub"

		display_alert "Adding" "Wireless drivers for Realtek 88x2cs chipsets ${rtl88x2csver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/jethome-ru/rtl88x2cs" "rtl88x2cs" "${rtl88x2csver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl88x2cs"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl88x2cs/"
		cp -R "${SRC}/cache/sources/rtl88x2cs/${rtl88x2csver#*:}"/{core,hal,include,os_dep,platform,halmac.mk,ifcfg-wlan0,rtl8822c.mk,runwpa,wlan0dhcp} \
		"$kerneldir/drivers/net/wireless/rtl88x2cs"

		# Makefile
		cp "${SRC}/cache/sources/rtl88x2cs/${rtl88x2csver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl88x2cs/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl88x2cs/${rtl88x2csver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl88x2cs/${rtl88x2csver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl88x2cs/Kconfig"

		# Adjust path
		sed -i 's/include $(src)\/rtl8822c.mk/include $(TopDIR)\/drivers\/net\/wireless\/rtl88x2cs\/rtl8822c.mk/' \
		"$kerneldir/drivers/net/wireless/rtl88x2cs/Makefile"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
		"$kerneldir/drivers/net/wireless/rtl88x2cs/Makefile"

		# Add to section Makefile
		 echo "obj-\$(CONFIG_RTL8822CS) += rtl88x2cs/" >> "$kerneldir/drivers/net/wireless/Makefile"
		 sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl88x2cs\/Kconfig"' \
		 "$kerneldir/drivers/net/wireless/Kconfig"
	fi


	# Bluetooth support for Realtek 8822CS (hci_ver 0x8) chipsets
	# For sunxi, these two patches are applied in a series.
	if linux-version compare "${version}" ge 5.17.3 ; then

		display_alert "Adding" "Bluetooth support for Realtek 8822CS (hci_ver 0x8) chipsets" "info"

		process_patch_file "${SRC}/patch/misc/bluetooth-rtl8822cs-hci_ver-0x8.patch" "applying"
		process_patch_file "${SRC}/patch/misc/Bluetooth-hci_h5-Add-power-reset-via-gpio-in-h5_btrt.patch" "applying"

	fi


	# Wireless drivers for Realtek 8723DS chipsets

	if linux-version compare "${version}" ge 5.17.3 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8723dsver="branch:master"

		display_alert "Adding" "Wireless drivers for Realtek 8723DS chipsets ${rtl8723dsver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/lwfinger/rtl8723ds" "rtl8723ds" "${rtl8723dsver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8723ds"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8723ds/"
		cp -R "${SRC}/cache/sources/rtl8723ds/${rtl8723dsver#*:}"/{core,hal,include,os_dep,platform} \
		"$kerneldir/drivers/net/wireless/rtl8723ds"

		# Makefile
		cp "${SRC}/cache/sources/rtl8723ds/${rtl8723dsver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl8723ds/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8723ds/${rtl8723dsver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8723ds/${rtl8723dsver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8723ds/Kconfig"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
		"$kerneldir/drivers/net/wireless/rtl8723ds/Makefile"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8723DS) += rtl8723ds/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8723ds\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

	fi

	# Wireless drivers for Realtek 8723DU chipsets

	if linux-version compare $version ge 5.17.3 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		display_alert "Adding" "Wireless drivers for Realtek 8723DU chipsets ${rtl8723duver}" "info"

		if [ "$EXTRAWIFI_LOCAL" == yes ]; then
			local rtl8723duver="branch:local_rtl8723du-rk"
			fetch_from_repo "$GITHUB_SOURCE/150balbes/wifi" "rtl8723du" "${rtl8723duver}" "yes"
		else
			if linux-version compare $version ge 5.12 ; then
				local rtl8723duver="branch:v5.13.4"
			else
				local rtl8723duver="branch:master"
			fi
			fetch_from_repo "$GITHUB_SOURCE/lwfinger/rtl8723du" "rtl8723du" "${rtl8723duver}" "yes"
		fi
		cd "$kerneldir" || exit
		rm -rf $kerneldir/drivers/net/wireless/rtl8723du
		mkdir -p $kerneldir/drivers/net/wireless/rtl8723du/
		cp -R ${SRC}/cache/sources/rtl8723du/${rtl8723duver#*:}/{core,hal,include,os_dep,platform} \
		$kerneldir/drivers/net/wireless/rtl8723du

		# Makefile
		cp ${SRC}/cache/sources/rtl8723du/${rtl8723duver#*:}/Makefile \
		$kerneldir/drivers/net/wireless/rtl8723du/Makefile

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
		$kerneldir/drivers/net/wireless/rtl8723du/Makefile

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8723DU) += rtl8723du/" >> $kerneldir/drivers/net/wireless/Makefile
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8723du\/Kconfig"' \
		$kerneldir/drivers/net/wireless/Kconfig

		process_patch_file "${SRC}/patch/misc/wireless-rtl8723du.patch" "applying"
	fi

	# Wireless drivers for Realtek 8822BS chipsets

	if linux-version compare "${version}" ge 5.17.3 && linux-version compare "${version}" le 5.19.2 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		display_alert "Adding" "Wireless drivers for Realtek 8822BS chipsets ${rtl8822bsver}" "info"

		local rtl8822bsver="branch:local_rtl8822bs"
		fetch_from_repo "$GITHUB_SOURCE/150balbes/wifi" "rtl8822bs" "${rtl8822bsver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8822bs"
		mkdir -p $kerneldir/drivers/net/wireless/rtl8822bs/
		cp -R "${SRC}/cache/sources/rtl8822bs/${rtl8822bsver#*:}"/{core,hal,include,os_dep,platform,bluetooth,getAP,rtl8822b.mk} \
		$kerneldir/drivers/net/wireless/rtl8822bs

		# Makefile
		cp "${SRC}/cache/sources/rtl8822bs/${rtl8822bsver#*:}/Makefile" \
		$kerneldir/drivers/net/wireless/rtl8822bs/Makefile

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8822bs/${rtl8822bsver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8822bs/${rtl8822bsver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8822bs/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8822BS) += rtl8822bs/" >> $kerneldir/drivers/net/wireless/Makefile
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8822bs\/Kconfig"' \
		$kerneldir/drivers/net/wireless/Kconfig

	fi

	# Exfat driver

	if linux-version compare "${version}" ge 5.17.3 && linux-version compare "${version}" le 5.19/2; then

		# attach to specifics tag or branch
		display_alert "Adding" "exfat driver ${exfatsver}" "info"

		local exfatsver="branch:master"
		fetch_from_repo "$GITHUB_SOURCE/arter97/exfat-linux" "exfat" "${exfatsver}" "yes"
		cd "$kerneldir" || exit
		mkdir -p $kerneldir/fs/exfat/
		cp -R "${SRC}/cache/sources/exfat/${exfatsver#*:}"/{*.c,*.h} \
		$kerneldir/fs/exfat/

		# Add to section Makefile
		echo "obj-\$(CONFIG_EXFAT_FS) += exfat/" >> $kerneldir/fs/Makefile

		# Makefile
		cat <<-EOF > "$kerneldir/fs/exfat/Makefile"
		# SPDX-License-Identifier: GPL-2.0-or-later
		#
		# Makefile for the linux exFAT filesystem support.
		#
		obj-\$(CONFIG_EXFAT_FS) += exfat.o
		exfat-y	:= inode.o namei.o dir.o super.o fatent.o cache.o nls.o misc.o file.o balloc.o xattr.o
		EOF

		# Kconfig
		sed  -i '$i\source "fs\/exfat\/Kconfig"' $kerneldir/fs/Kconfig
		cp "${SRC}/cache/sources/exfat/${exfatsver#*:}/Kconfig" \
		"$kerneldir/fs/exfat/Kconfig"

	fi

}
