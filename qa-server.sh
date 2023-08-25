#!/bin/bash

APP_NAME="exp-server"
DIR_PATH="/workspace/exp-server-qa"

# 현재 브랜치 이름 받아오기
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 인자
COMMAND=$1
N_OPTION=false

# SIGINT 핸들러
handle_sigint() {
    echo ""
    echo "작업을 중지합니다"
}

# 커맨드 없으면 중료
if [ -z "$COMMAND" ]; then
    exit 0
fi

# 인자 처리
shift
while [[ "$#" -gt 0 ]]; do
    case $1 in
    start) shift ;;
    -n | --no-build)
        N_OPTION=true
        shift
        ;;
    *)
        echo "허용되지 않은 인자입니다"
        exit 1
        ;;
    esac
done

trap 'handle_sigint' SIGINT
# 커맨드별 분기처리
case $COMMAND in
start)
    # 디렉토리 이동
    cd $DIR_PATH

    # 실행중인 앱이 있는지에 따라 분기하여 실행
    start_app() {
        if pm2 jlist | grep -q "\"name\":\"$APP_NAME\""; then
            pm2 reload $APP_NAME
        else
            pm2 start
        fi
    }

    # --no-build 옵션 있으면 바로 실행
    if $N_OPTION; then
        start_app
        exit 0
    fi

    # 브랜치 상태 최신화
    git branch --set-upstream-to=origin/$CURRENT_BRANCH $CURRENT_BRANCH
    git pull
    yarn

    # 앱 실행
    start_app
    ;;
reload)
    if pm2 jlist | grep -q "\"name\":\"$APP_NAME\""; then
        pm2 reload $APP_NAME
    else
        echo "실행중인 앱이 없습니다"
    fi
    ;;
stop)
    if pm2 jlist | grep -q "\"name\":\"$APP_NAME\""; then
        pm2 delete $APP_NAME
    else
        echo "실행중인 앱이 없습니다"
    fi
    ;;
esac
