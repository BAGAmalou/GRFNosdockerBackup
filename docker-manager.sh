#!/bin/bash

# 检查whiptail是否安装
if ! command -v whiptail &> /dev/null; then
    echo "正在安装whiptail..."
    sudo apt-get update
    sudo apt-get install -y whiptail
fi

# 主备份函数
backup_images() {
    # 获取所有Docker镜像
    images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>")
    if [ -z "$images" ]; then
        whiptail --msgbox "未找到Docker镜像！" 10 30
        return 1
    fi

    # 选择备份目录
    backup_dir=$(whiptail --inputbox "请输入备份目录完整路径：" 10 60 /vol2/1001/docker_backups 3>&1 1>&2 2>&3)
    if [ -z "$backup_dir" ]; then
        whiptail --msgbox "必须指定备份目录！" 10 30
        return 1
    fi
    
    # 创建目录（如果不存在）
    mkdir -p "$backup_dir"

    # 进度条计数
    total=$(echo "$images" | wc -l)
    count=0

    # 逐个备份镜像
    for img in $images; do
        # 生成文件名
        filename=$(echo "$img" | sed 's/[^a-zA-Z0-9._-]/_/g').tar
        save_path="$backup_dir/$filename"
        
        # 更新进度
        ((count++))
        percentage=$((count*100/total))
        echo "XXX"
        echo "$percentage"
        echo "正在备份: $img → $filename ($count/$total)"
        echo "XXX"
        
        # 执行备份
        docker save -o "$save_path" "$img" 2>&1 | tee -a "$backup_dir/backup.log"
        
    done | whiptail --gauge "备份Docker镜像中..." 10 60 0

    # 完成提示
    whiptail --msgbox "备份完成！\n备份目录: $backup_dir\n日志文件: $backup_dir/backup.log" 12 60
}

# 主恢复函数
restore_images() {
    # 选择备份目录
    backup_dir=$(whiptail --inputbox "请输入备份目录完整路径：" 10 60 /vol2/1001/docker_backups 3>&1 1>&2 2>&3)
    
    if [ -z "$backup_dir" ]; then
        whiptail --msgbox "必须指定备份目录！" 10 30
        return 1
    fi
    
    if [ ! -d "$backup_dir" ]; then
        whiptail --msgbox "备份目录不存在！" 10 30
        return 1
    fi

    # 获取所有.tar备份文件
    backup_files=()
    while IFS= read -r -d $'\0' file; do
        backup_files+=("$file" "$(basename "$file")" OFF)
    done < <(find "$backup_dir" -maxdepth 1 -type f -name "*.tar" -print0)
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        whiptail --msgbox "未找到备份文件！" 10 30
        return 1
    fi

    # 让用户选择要恢复的文件
    selected_files=$(whiptail --title "选择要恢复的镜像" --checklist \
        "使用空格键选择/取消选择镜像" 20 60 10 \
        "${backup_files[@]}" \
        3>&1 1>&2 2>&3)
    
    if [ -z "$selected_files" ]; then
        whiptail --msgbox "未选择任何镜像！" 10 30
        return 1
    fi

    # 处理选中的文件
    count=0
    total=$(echo "$selected_files" | wc -w)
    
    # 创建临时目录用于进度显示
    tmpfile=$(mktemp)
    
    (
        for file in $selected_files; do
            # 移除引号
            clean_file=$(echo "$file" | tr -d '"')
            filename=$(basename "$clean_file")
            
            # 更新进度
            ((count++))
            percentage=$((count*100/total))
            echo "XXX"
            echo "$percentage"
            echo "正在恢复: $filename ($count/$total)"
            echo "XXX"
            
            # 执行恢复
            docker load -i "$clean_file" 2>&1 | tee -a "$backup_dir/restore.log"
            sleep 1
        done
    ) | whiptail --gauge "恢复Docker镜像中..." 10 60 0
    
    # 完成提示
    whiptail --msgbox "恢复完成！\n已恢复 $count 个镜像\n日志文件: $backup_dir/restore.log" 12 60
}

# 批量部署函数（含自定义目录）
deploy_images() {
    # 获取所有Docker镜像
    images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>")
    if [ -z "$images" ]; then
        whiptail --msgbox "未找到Docker镜像！" 10 30
        return 1
    fi

    # 让用户选择要部署的镜像
    image_list=()
    while IFS= read -r img; do
        image_list+=("$img" "" OFF)
    done <<< "$images"
    
    selected_images=$(whiptail --title "选择要部署的镜像" --checklist \
        "使用空格键选择/取消选择镜像" 20 60 10 \
        "${image_list[@]}" \
        3>&1 1>&2 2>&3)
    
    if [ -z "$selected_images" ]; then
        whiptail --msgbox "未选择任何镜像！" 10 30
        return 1
    fi

    # 选择部署目录
    deploy_dir=$(whiptail --inputbox "请输入部署目录完整路径：" 10 60 /vol2/1001/docker_data 3>&1 1>&2 2>&3)
    if [ -z "$deploy_dir" ]; then
        whiptail --msgbox "必须指定部署目录！" 10 30
        return 1
    fi
    
    # 创建部署目录
    mkdir -p "$deploy_dir"
    
    # 输入部署参数
    deploy_params=$(whiptail --inputbox "输入部署参数（可选）：\n例如：-p 8080:80 --name my-container" \
        12 60 3>&1 1>&2 2>&3)
    
    # 处理选中的镜像
    count=0
    total=$(echo "$selected_images" | wc -w)
    
    # 创建临时文件用于进度显示
    tmpfile=$(mktemp)
    
    (
        for img in $selected_images; do
            # 移除引号
            clean_img=$(echo "$img" | tr -d '"')
            
            # 为每个容器创建专用目录
            container_dir=$(echo "$clean_img" | sed 's/[^a-zA-Z0-9._-]/_/g')
            full_deploy_dir="$deploy_dir/$container_dir"
            mkdir -p "$full_deploy_dir"
            
            # 更新进度
            ((count++))
            percentage=$((count*100/total))
            echo "XXX"
            echo "$percentage"
            echo "正在部署: $clean_img ($count/$total)"
            echo "部署目录: $full_deploy_dir"
            echo "XXX"
            
            # 执行部署（包含自定义目录）
            docker run -d \
                -v "$full_deploy_dir:/app/data" \
                $deploy_params \
                $clean_img 2>&1 | tee -a "$deploy_dir/deploy.log"
                
            sleep 1
        done
    ) | whiptail --gauge "部署Docker容器中..." 10 60 0
    
    # 完成提示
    whiptail --msgbox "部署完成！\n已部署 $count 个容器\n部署目录: $deploy_dir\n日志文件: $deploy_dir/deploy.log" 12 60
}

# 主菜单
main_menu() {
    while true; do
        choice=$(whiptail --menu "Docker镜像管理" 15 60 4 \
            "1" "备份镜像" \
            "2" "恢复镜像" \
            "3" "批量部署（含自定义目录）" \
            "4" "退出" \
            3>&1 1>&2 2>&3)
        
        case $choice in
            1) backup_images ;;
            2) restore_images ;;
            3) deploy_images ;;
            4) break ;;
            *) whiptail --msgbox "无效选择！" 10 30 ;;
        esac
    done
}

# 检查Docker是否可用
if ! command -v docker &> /dev/null; then
    whiptail --msgbox "Docker未安装！请先安装Docker。" 10 50
    exit 1
fi

# 执行主菜单
main_menu