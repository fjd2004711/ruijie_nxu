include $(TOPDIR)/rules.mk

PKG_NAME:=netlogin-nxu
PKG_VERSION:=1.1.1
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/netlogin-nxu
  SECTION:=net
  CATEGORY:=Network
  TITLE:=NXU NetLogin authentication service
  URL:=https://github.com/fjd2004711/ruijie_nxu
  DEPENDS:=+curl +ca-bundle +uci +luci-base
  DEFAULT:=y
  PKGARCH:=all
endef

define Package/netlogin-nxu/description
  宁夏大学校园网 NetLogin OpenWrt 服务，支持 UCI 配置、procd 持久登录和系统日志。
endef

define Package/netlogin-nxu/conffiles
/etc/config/netlogin-nxu
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./files/* $(PKG_BUILD_DIR)/
	$(CP) ./../../netlogin_openwrt.sh $(PKG_BUILD_DIR)/usr/bin/netlogin_openwrt.sh
endef

define Build/Compile
endef

define Package/netlogin-nxu/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/netlogin-nxu
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/usr/bin/netlogin_openwrt.sh $(1)/usr/bin/netlogin_openwrt.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/etc/init.d/netlogin-nxu $(1)/etc/init.d/netlogin-nxu
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/etc/config/netlogin-nxu $(1)/etc/config/netlogin-nxu
	$(INSTALL_DATA) ./luci/controller/netlogin_nxu.lua $(1)/usr/lib/lua/luci/controller/netlogin_nxu.lua
	$(INSTALL_DATA) ./luci/model/cbi/netlogin-nxu/config.lua $(1)/usr/lib/lua/luci/model/cbi/netlogin-nxu/config.lua
	$(INSTALL_DATA) ./luci/menu.d/luci-app-netlogin-nxu.json $(1)/usr/share/luci/menu.d/luci-app-netlogin-nxu.json
	$(INSTALL_DATA) ./luci/acl.d/luci-app-netlogin-nxu.json $(1)/usr/share/rpcd/acl.d/luci-app-netlogin-nxu.json
	chmod 600 $(1)/etc/config/netlogin-nxu
endef

define Package/netlogin-nxu/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || /etc/init.d/netlogin-nxu enable
exit 0
endef

$(eval $(call BuildPackage,netlogin-nxu))
