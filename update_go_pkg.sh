#!/usr/bin/env bash
eza --header --group-directories-first --color-scale all --color always --icons always --group -b "${GOBIN}"
echo ""
echo "Mise à jour en cours..."
echo ""

go install github.com/zi0p4tch0/radiogogo@latest
go install github.com/ashish0kumar/stormy@latest
go install github.com/programmersd21/zap/cmd/zap@latest
go install github.com/xdagiz/xytz@latest
go install github.com/renatoworks/oh-my-reddit@latest
go install github.com/showwin/speedtest-go@latest
go install github.com/Foxemsx/riptide/cmd/riptide@latest
go install github.com/nolight132/nls/cmd/nls@latest
go install github.com/0xjuanma/golazo@latest
go install github.com/mr-karan/doggo/cmd/doggo@latest
go install github.com/heymaikol/network-doctor@latest

echo ""
echo "Mise à jour terminée"
echo ""

eza -l --header --group-directories-first --color-scale all --color always --icons always --group -b "${GOBIN}"
