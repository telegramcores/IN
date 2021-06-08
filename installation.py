import sys
import subprocess as sp

import compiling
from utils import call_cmd_and_print_cmd, source

def emerge_base():
    call_cmd_and_print_cmd('''echo 'EMERGE_DEFAULT_OPTS="--jobs --quiet-build=y"' >> /etc/portage/make.conf''')
    call_cmd_and_print_cmd('''echo 'PORTAGE_BINHOST="https://mirror.yandex.ru/calculate/grp/x86_64"' >> /etc/portage/make.conf''')
    call_cmd_and_print_cmd('emerge-webrsync')
    call_cmd_and_print_cmd('emerge -gK --oneshot sys-apps/portage')
    call_cmd_and_print_cmd('emerge -gK app-portage/gentoolkit')

    
    #Отключаю выбор профиля, 1 по умолчанию
    #print(call_cmd_and_print_cmd('eselect profile list'))
    #print('select profile:')
    # # 1 - сервер, 5 - desktop (echo 1)
    #profile_choice = sp.check_output('read -t 20 CHOICE; [ -z $CHOICE ] && echo 1 || echo $CHOICE', shell=True).strip().decode()
    #call_cmd_and_print_cmd(f'eselect profile set {profile_choice}')
    #print(call_cmd_and_print_cmd('eselect profile list'))
    #call_cmd_and_print_cmd ('env-update && source /etc/profile')
    #------------------------------------------------------------
    call_cmd_and_print_cmd('emerge -gK app-portage/cpuid2cpuflags')
    call_cmd_and_print_cmd('echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags')


def install(boot_device: str):
    source('/etc/profile')
    call_cmd_and_print_cmd(f'mount {boot_device} /boot')
    call_cmd_and_print_cmd('mkdir /home/gentoo')
    #emerge_base()
    #compiling.compile(boot_device)
    #call_cmd_and_print_cmd('rc-update add dhcpcd default')
    #call_cmd_and_print_cmd('emerge -gK lvm2')
    #call_cmd_and_print_cmd('rc-update add lvmetad boot')
