#!/bin/bash
set -euo pipefail

# $1 = カーネル名 (例: can0)
# $2 = ハードウェアID (例: 00112233)
ORIG_NAME=${1-}
HW_ID=${2-}

LOCKFILE="/var/tmp/can_altname.lock"

if [ -z "$ORIG_NAME" ] || [ -z "$HW_ID" ]; then
    logger -t assign_can_altname "Error - Missing arguments"
    exit 1
fi

(
    # 排他制御
    flock -w 5 9 || { logger -t assign_can_altname "Failed to acquire lock"; exit 1; }

    PARENT_NET_DIR="/sys/class/net/$ORIG_NAME/device/net"
    CH_INDEX=0
    CH_TOTAL=1

    # チャンネル総数と現在のチャンネルインデックスを特定
    if [ -d "$PARENT_NET_DIR" ]; then
        CAN_DEVS=$(ls "$PARENT_NET_DIR" | grep '^can' | sort -V || true)
        CH_TOTAL=$(echo "$CAN_DEVS" | grep -c '^can' || true)

        for dev in $CAN_DEVS; do
            if [ "$dev" = "$ORIG_NAME" ]; then
                break
            fi
            CH_INDEX=$((CH_INDEX + 1))
        done
    fi

    # ---------------------------------------------------------
    # <iSerial>(<n個目のデバイス>)c<channel> フォーマットの生成
    # ---------------------------------------------------------
    COUNTER=0
    while true; do
        # 1台目はサフィックスなし、2台目以降は .1, .2 ... を付与
        if [ "$COUNTER" -eq 0 ]; then
            DEV_SUFFIX=""
        else
            DEV_SUFFIX=".${COUNTER}"
        fi

        # チャンネル総数に応じて末尾のフォーマットを切り替え
        if [ "$CH_TOTAL" -gt 1 ]; then
            TARGET_ALTNAME="${HW_ID}${DEV_SUFFIX}c${CH_INDEX}"
        else
            TARGET_ALTNAME="${HW_ID}${DEV_SUFFIX}"
        fi

        # 生成した altname がシステム上に存在しないか確認
        if ! /usr/sbin/ip link show dev "$TARGET_ALTNAME" >/dev/null 2>&1; then
            # 存在しないため、この名前に決定してループを抜ける
            break
        fi

        # 既に存在する場合は次の連番へ
        COUNTER=$((COUNTER + 1))
        if [ "$COUNTER" -gt 10 ]; then
            logger -t assign_can_altname "Error - Too many identical IDs (${HW_ID})"
            exit 1
        fi
    done

    # 決定した altname を付与
    if /usr/sbin/ip link property add dev "$ORIG_NAME" altname "$TARGET_ALTNAME"; then
        logger -t assign_can_altname "Success - Assigned $TARGET_ALTNAME to $ORIG_NAME"
    else
        logger -t assign_can_altname "Error - Failed to Assign altname to $ORIG_NAME"
    fi

) 9> "$LOCKFILE"
