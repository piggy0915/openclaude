#!/bin/bash
# 便捷进入 Hermes 容器脚本
# 位置：./data/hermes/scripts/enter-hermes.sh

docker exec -it hermes bash -c "
    if [ -f /opt/hermes/.venv/bin/activate ]; then
        source /opt/hermes/.venv/bin/activate
        echo '✓ Virtual environment activated'
    else
        echo '⚠️  Virtual environment not found'
    fi
    echo '✓ You can now use: hermes --help'
    echo ''
    exec bash
"