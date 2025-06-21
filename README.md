# Docker 镜像备份脚本使用说明
## 一、脚本功能概述
本脚本用于对 Docker 镜像进行逐个备份操作，支持通过图形化交互流程配置备份路径，执行镜像备份，并提供备份进度展示、完成提示及常见问题解决方案，利用 whiptail （适用于飞牛 OS 环境 ）实现图形化界面，方便用户操作与监控备份过程。
## 二、环境依赖
需安装 whiptail 工具（脚本会自动检查并尝试安装，若安装失败需手动处理 ）。
需确保系统已安装 Docker，脚本会提前检查 Docker 可用性，未安装则无法执行备份。
## 三、操作步骤
###### （一）前期准备 - 创建文件夹与获取脚本
创建存储文件夹
切换至指定存储路径（以 vol2 为存储空间、1001 为用户目录标识示例 ）：
```bash
cd /vol2/1001
```
创建 Docker 专用文件夹：
```bash
mkdir docker
```
拉取备份脚本
通过 Gitee 仓库获取自动化脚本并命名为指定文件名：
```bash
wget https://gitee.com/8AGAa1ou/6rnDS-Docker-Backup-demo/raw/main/docker-manager.sh -O docker-manager.sh
```
###### （二）权限配置与脚本运行
权限配置
为脚本文件赋予可执行权限（以脚本路径 /vol2/1001/docker/docker-manager.sh 为例 ）：
```bash
chmod +x /vol2/1001/docker/docker-manager.sh
```
脚本运行方式有两种方法

①绝对路径执行：直接通过完整路径调用脚本：
```bash
/vol2/1001/docker/docker-manager.sh
```

②目录切换后执行：先切换到脚本所在目录，再执行脚本（假设脚本在 docker 目录 ）：
```bash
cd /vol2/1001/docker./docker-backup-gui.sh 
```

###### （三）图形化交互流程
:star: 备份目录配置

运行脚本后，在弹出的图形化界面输入完整备份路径（如 /vol2/1001/ ），点击 OK 确认。

:star: 进度展示

系统自动显示备份进度条，直观呈现备份执行进度。

:star: 完成提示

备份完成后，展示备份的目录路径及日志文件位置，日志可用于后续故障排查与操作追溯。
###### 四、常见问题解决
进度条不显示
尝试使用简单显示方式修改脚本内相关备份命令，示例：
```bash
echo "备份进度：$count/$total - $img"
docker save -o "$save_path" "$img" 2>&1 | tee -a "$backup_dir/backup.log"
```

权限问题
若遇到权限不足，可使用 sudo 赋予权限（以 docker-backup-gui.sh 为例 ）：
```bash
sudo chmod +x /vol2/1001/docker/docker-backup-gui.sh
```
无交互终端问题
在 SSH 命令中添加 -t 参数，示例：
```bash
ssh -t user@飞牛OS-IP /vol2/1001/docker/docker-backup-gui.sh
```
###### 五、脚本源码说明
 脚本基于 bash 编写，使用 whiptail 实现图形化界面，主要功能逻辑包括：
 检查 whiptail 与 Docker 可用性，自动安装缺失的 whiptail。
 定义 backup_images 函数，实现获取 Docker 镜像列表、交互配置备份目录、创建目录、逐个备份镜像（含进度统计与日志记录 ）、完成提示等流程。
 执行主函数 backup_images 启动备份操作，完整源码可查看脚本文件内容，便于自定义修改与扩展。