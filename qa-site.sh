#!/bin/bash

APP_NAME="exp-site"
STORYBOOK_APP_NAME="exp-storybook"
DIR_PATH="/workspace/exp-site-qa"
CONFIG_PATH="$DIR_PATH/config/next.config.js"
TEMP_PATH="/workspace/temp.txt"
APP_PATH="$DIR_PATH/src/pages/_app.jsx"
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
    rm -rf $DIR_PATH/.next_temp
    if [ -d "$DIR_PATH/.next.bak" ]; then
        rm -rf $DIR_PATH/.next
        mv $DIR_PATH/.next.bak $DIR_PATH/.next
    fi

    # 빌드 로그 삭제
    if [ -e "$TEMP_PATH" ]; then
        rm -rf $TEMP_PATH
    fi
}
handle_sigint() {
    echo ""
    echo "작업을 중지합니다"
    delete_state_file
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
    trap 'handle_sigint_start' SIGINT
    # 실행중이 앱이 있는지에 따라 분기하여 실행
    start_app() {
        if pm2 jlist | grep -q "\"name\":\"$APP_NAME\""; then
            pm2 reload $APP_NAME
        else
            pm2 start
        fi
    }
    start_storybook() {
        npm run build:storybook
        if pm2 jlist | grep -q "\"name\":\"$STORYBOOK_APP_NAME\""; then
            pm2 reload $STORYBOOK_APP_NAME
        else
            pm2 start npm --name $STORYBOOK_APP_NAME -- run storybook:prd
        fi
    }

    # --no-build 옵션 있으면 바로 실행
    if $N_OPTION; then
        start_app
        start_storybook
        delete_state_file
        exit 0
    fi

    # release 브랜치 받아오기
    git remote update
    # git checkout $(git ls-remote --heads origin | awk -F/ '/\/release\// {print $3"/"$4}')
    # 브랜치 상태 최신화
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    git branch --set-upstream-to=origin/$current_branch $current_branch
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
        mv $DIR_PATH/.next $DIR_PATH/.next.bak
        mv $DIR_PATH/.next_temp $DIR_PATH/.next
        rm -rf $DIR_PATH/.next.bak
        delete_temp_files
        start_app
        start_storybook
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

delete_state_file
