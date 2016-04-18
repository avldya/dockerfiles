#!/bin/bash
# this is kind of an expensive check, so let's not do this twice if we
# are running more than one validate bundlescript
VALIDATE_REPO='https://gogs.boxobox.xyz/xataz/dockerfiles.git'
VALIDATE_BRANCH='master'
VALIDATE_USER='xataz'
DOCKER_PULL=$1

VALIDATE_HEAD="$(git rev-parse --verify HEAD)"

git fetch -q "$VALIDATE_REPO" "refs/heads/$VALIDATE_BRANCH"
VALIDATE_UPSTREAM="$(git rev-parse --verify FETCH_HEAD)"

VALIDATE_COMMIT_DIFF="$VALIDATE_UPSTREAM...$VALIDATE_HEAD"

validate_diff() {
	if [ "$VALIDATE_UPSTREAM" != "$VALIDATE_HEAD" ]; then
		git diff "$VALIDATE_COMMIT_DIFF" "$@"
	else
		git diff HEAD~ "$@"
	fi
}


deps_pull() {
    image=$1
    # alpine/3.3/.tags:3.3 latest
    images_list=""
    image_path=${build_dir}

    while true; do
        image=$(grep 'FROM' ${image_path}/Dockerfile | awk '{print $2}')
        if [[ $image == ${VALIDATE_USER}* ]];then
            image_name=$(echo $image | sed 's|\(.*\)/\(.*\):\(.*\)|\2|g')
            image_tag=${latest-$(echo $image | sed 's|\(.*\)/\(.*\):\(.*\)|\3|g')}
            [ $image_name == $image_tag ] && $image_tag='latest'
            
            if [ "$(find ${image_name} -type f -name .tags)" == "" ]; then
                image_path=${image_name}
            else
                image_path=$(dirname $(grep ${image_tag} $(find ${image_name} -type f -name .tags) | cut -d: -f1))
            fi
            images_list="${image_name}|${image_tag}|${image_path} "${images_list}
        else
            image_name=$(echo $image | sed 's|\(.*\):\(.*\)|\1|g')
            image_tag=$(echo $image | sed 's|\(.*\):\(.*\)|\2|g')
            docker pull ${image_name}:${image_tag}
            break
        fi
    done

    for f in "${images_list[@]}"; do
        f_name=${VALIDATE_USER}/$(echo $f | cut -d"|" -f1)
        f_tag=$(echo $f | cut -d"|" -f2)
        f_path=$(echo $f | cut -d"|" -f3)
        build_image ${f_name} ${f_path}
    done 

}

build_image() {
    image_name=$1
    image_dir=$2

    if [ -e "${image_dir}/.tags" ]; then
        tags_list=$(cat ${image_dir}/.tags)
    else
        tags_list="latest"
    fi

    for tag in $tags_list; do
        docker build -t ${VALIDATE_USER}/${image_name}:${tag} ${image_dir}
        if [ $DOCKER_PULL == "push" ]; then
            docker push ${VALIDATE_USER}/${image_name}:${tag}
        fi
        echo "                       ---                                   "
        echo "Successfully built ${VALIDATE_USER}/${image_name}:${tag} with context ${image_dir}"
        echo "                       ---                                   "
        if [ $DOCKER_PULL == "push" ]; then
            docker push ${VALIDATE_USER}/${image_name}:${tag}
            echo "                       ---                                   "
                echo "Successfully push ${VALIDATE_USER}/${image_name}:${tag}"
            echo "                       ---                                   "
        fi
    done
}

# get the dockerfiles changed
IFS=$'\n'
files=( $(validate_diff --name-only -- '*Dockerfile') )
unset IFS

# build the changed dockerfiles
for f in "${files[@]}"; do
	image=${f%Dockerfile}
	base=${image%%\/*}
	build_dir=$(dirname $f)

    deps_pull ${base}
    build_image ${base} ${build_dir}
done
