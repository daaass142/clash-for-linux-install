[Unit]
Description=placeholder_kernel_desc
After=network.target NetworkManager.service systemd-networkd.service iwd.service

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
# Least privilege: TUN/routing needs NET_ADMIN/NET_RAW; do not grant ptrace,
# DAC override, system-time or other host-wide capabilities by default.
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW
NoNewPrivileges=true
PrivateTmp=true
ProtectControlGroups=true
ProtectKernelLogs=true
RestrictSUIDSGID=true
LockPersonality=true
Restart=always
ExecStartPre=/usr/bin/sleep 1s
ExecStart=placeholder_cmd_full
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
