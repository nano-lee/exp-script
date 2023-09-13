#!/bin/bash

APP_NAME="exp-site"
DIR_PATH="/workspace/exp-site-qa"
CONFIG_PATH="$DIR_PATH/config/next.config.js"
TEMP_PATH="/workspace/temp.txt"
APP_PATH="$DIR_PATH/src/pages/_app.jsx"

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
delete_temp_files() {
    # 임시 설정파일 삭제
    if [ -e "$CONFIG_PATH.bak" ]; then
        mv $CONFIG_PATH.bak $CONFIG_PATH
    fi

    # package.json 복구
    if [ -e "$DIR_PATH/package.json.bak" ]; then
        mv $DIR_PATH/package.json.bak $DIR_PATH/package.json
        mv $DIR_PATH/package-lock.json.bak $DIR_PATH/package-lock.json
    fi

    # _app.jsx 복구
    if [ -e "$APP_PATH.bak" ]; then
        mv $APP_PATH.bak $APP_PATH
    fi

    # 임시 빌드파일 삭제
    rm -rf $DIR_PATH/src/.next_temp
    if [ -d "$DIR_PATH/src/.next.bak" ]; then
        rm -rf $DIR_PATH/src/.next
        mv $DIR_PATH/src/.next.bak $DIR_PATH/src/.next
    fi

    # 빌드 로그 삭제
    if [ -e "$TEMP_PATH" ]; then
        rm -rf $TEMP_PATH
    fi
}
handle_sigint_start() {
    handle_sigint
    delete_temp_files
    exit 1
}

# 커맨드 없으면 종료
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

# 디렉토리 이동
cd $DIR_PATH

trap 'handle_sigint' SIGINT
# 커맨드별 분기처리
case $COMMAND in
start)
    trap 'handle_sigint_start' SIGINT
    # 실행중이 앱이 있는지에 따라 분기하여 실행
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
    npm install
    # inspx 설치
    cp $DIR_PATH/package.json $DIR_PATH/package.json.bak
    cp $DIR_PATH/package-lock.json $DIR_PATH/package-lock.json.bak
    npm install inspx --save
    # inspx 적용
    cp $APP_PATH $APP_PATH.bak
    sed -i -e '1s/^/import Inspect from '\''inspx'\'';\n/' -e "s/<>/<Inspect disabled={false}>/g" -e "s/<\/>/<\/Inspect>/g" $APP_PATH
    # 실행중인 앱에 빌드가 영향을 끼치지 않도록 next config 수정
    cp $CONFIG_PATH $CONFIG_PATH.bak
    sed -i '/const nextConfig = {/a distDir: ".next_temp",' $CONFIG_PATH
    # 빌드
    npm run build:prd | tee $TEMP_PATH
    # 빌드 성공시 앱 실행
    if [ ! -z "$(grep 'Route (pages)' $TEMP_PATH)" ]; then
        mv $DIR_PATH/src/.next $DIR_PATH/src/.next.bak
        mv $DIR_PATH/src/.next_temp $DIR_PATH/src/.next
        rm -rf $DIR_PATH/src/.next.bak
        delete_temp_files
        start_app
    else
        delete_temp_files
    fi
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
