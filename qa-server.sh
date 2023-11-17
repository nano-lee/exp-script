#!/bin/bash

APP_NAME="exp-server"
DIR_PATH="/workspace/exp-server-qa"
STATE_PATH="/workspace/script.state"

# 인자
COMMAND=$1
N_OPTION=false

# SIGINT 핸들러
delete_state_file() {
    # 스크립트 상태 파일 삭제
    if [ -e "$STATE_PATH" ]; then
        rm $STATE_PATH
    fi
}
handle_sigint() {
    echo ""
    echo "작업을 중지합니다"
    delete_state_file
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

# 스크립트 실행중 여부 확인
if [ -e "$STATE_PATH" ]; then
    echo "스크립트가 이미 실행중입니다."
    exit 1
fi

# 스크립트 상태 저장
touch $STATE_PATH
echo "$COMMAND" >>$STATE_PATH

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
        delete_state_file
        exit 0
    fi

    # release 브랜치 받아오기
    git fetch
    git checkout $(git ls-remote --heads origin | awk -F/ '/\/release\// {print $3"/"$4}')
    # 브랜치 상태 최신화
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    git branch --set-upstream-to=origin/$current_branch $current_branch
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

delete_state_file
