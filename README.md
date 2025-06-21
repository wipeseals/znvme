# toynvme

A simple user-space NVMe driver for Linux.

---

## Driver Setup

本ドライバを利用するには、NVMeデバイスをカーネル標準の`nvme`ドライバからユーザ空間でアクセス可能な`uio_pci_generic`ドライバへ切り替える必要があります。  
この切り替えにより、ユーザ空間プログラムがデバイスのレジスタ等へ直接アクセスできるようになります。

切り替えを手軽に行うためのスクリプトが`misc/`ディレクトリに用意されています。

### Listing NVMe devices

まず、システムに接続されているNVMeデバイスを確認します。  
以下のコマンドは、`nvme`ドライバがバインドされている状態でのデバイス一覧表示例です。

```bash
user in 🌐 nbg9 in toynvme on  master [!?] via ↯ v0.14.1 via ❄️  impure (nix-shell-env) 
❯ sudo ./misc/list.sh
# Listing NVMe devices
Node                  Generic               SN                   Model                                    Namespace  Usage                      Format           FW Rev  
--------------------- --------------------- -------------------- ---------------------------------------- ---------- -------------------------- ---------------- --------
/dev/nvme0n1          /dev/ng0n1            Z4HF716NF88S         KIOXIA-EXCERIA with Heatsink SSD         0x1          1.02  TB /   1.02  TB    512   B +  0 B   AJRA4101
/dev/nvme1n1          /dev/ng1n1            201008800819         WDC WD BLACK SDBPNTY-512G-1106           0x1        512.11  GB / 512.11  GB    512   B +  0 B   HPS2    
/dev/nvme2n1          /dev/ng2n1            TTSMA2513X09608      TWSC TSC3AN512-F8T40S                    0x1        512.11  GB / 512.11  GB    512   B +  0 B   SN13126 

# Listing NVMe devices with PCI addresses, VID, PID, and manufacturer/model info
PCI Address: 01:00.0, VID: 15b7, PID: 5006, Info: Sandisk Corp SanDisk Extreme Pro / WD Black SN750 / PC SN730 / Red SN700 NVMe SSD
PCI Address: 06:00.0, VID: 1e0f, PID: 000d, Info: KIOXIA Corporation NVMe SSD Controller XG7
PCI Address: 07:00.0, VID: 1e4b, PID: 1202, Info: MAXIO Technology (Hangzhou) Ltd. NVMe SSD Controller MAP1202 (DRAM-less) (rev 01)
```

各デバイスのPCIアドレスやベンダID/プロダクトIDも確認できます。  
この情報は後述のドライバ切り替え時に必要となります。

### Binding to the uio_pci_generic driver

NVMeデバイスを`nvme`ドライバからアンバインドし、`uio_pci_generic`ドライバへバインドします。  
下記のコマンド例は、PCIアドレス`0000:06:00.0`のデバイスを切り替える手順と、その実行ログです。

```bash
user in 🌐 nbg9 in toynvme on  master [!?] via ↯ v0.14.1 via ❄️  impure (nix-shell-env) 
❯ sudo ./misc/bind_uio.sh 0000:06:00.0 1e0f 000d
Unbound 0000:06:00.0 from nvme driver.
grep: /sys/bus/pci/drivers/uio_pci_generic/new_id: Permission denied
Bound 0000:06:00.0 to uio_pci_generic driver.
Bound 0000:06:00.0 to uio_pci_generic driver.
Successfully bound 0000:06:00.0 to uio_pci_generic driver.
06:00.0 Non-Volatile memory controller: KIOXIA Corporation NVMe SSD Controller XG7
        Subsystem: KIOXIA Corporation NVMe SSD Controller XG7
        Kernel driver in use: uio_pci_generic
        Kernel modules: nvme
```

`grep: /sys/bus/pci/drivers/uio_pci_generic/new_id: Permission denied` という警告が出る場合は、管理者権限で実行されているか確認してください。  
バインド後、`Kernel driver in use: uio_pci_generic`となっていれば切り替え成功です。

#### Checking the unbinded device

`uio_pci_generic`にバインドしたデバイスは、`nvme`コマンド等からは見えなくなります。  
下記は切り替え後の`nvme list`実行例です。

```bash
user in 🌐 nbg9 in toynvme on  master [!?] via ↯ v0.14.1 via ❄️  impure (nix-shell-env) 
❯ sudo nvme list
Node                  Generic               SN                   Model                                    Namespace  Usage                      Format           FW Rev  
--------------------- --------------------- -------------------- ---------------------------------------- ---------- -------------------------- ---------------- --------
/dev/nvme1n1          /dev/ng1n1            201008800819         WDC WD BLACK SDBPNTY-512G-1106           0x1        512.11  GB / 512.11  GB    512   B +  0 B   HPS2    
/dev/nvme2n1          /dev/ng2n1            TTSMA2513X09608      TWSC TSC3AN512-F8T40S                    0x1        512.11  GB / 512.11  GB    512   B +  0 B   SN13126 
```

### Unbinding from the uio_pci_generic driver and binding back to the nvme driver

作業終了後は、デバイスを元の`nvme`ドライバへ戻すことができます。  
以下はアンバインド・再バインドの手順とその実行ログです。

```bash
user in 🌐 nbg9 in toynvme on  master [!?] via ↯ v0.14.1 via ❄️  impure (nix-shell-env) 
❯ sudo ./misc/unbind_uio.sh 0000:06:00.0
Unbound 0000:06:00.0 from uio_pci_generic driver.
Bound 0000:06:00.0 to nvme driver.
Successfully bound 0000:06:00.0 to nvme driver.
06:00.0 Non-Volatile memory controller: KIOXIA Corporation NVMe SSD Controller XG7
        Subsystem: KIOXIA Corporation NVMe SSD Controller XG7
        Kernel driver in use: nvme
        Kernel modules: nvme
```

#### Listing NVMe devices again

再度`nvme`ドライバに戻すと、`nvme list`コマンドでデバイスが再び表示されます。

```bash
user in 🌐 nbg9 in toynvme on  master [!?] via ↯ v0.14.1 via ❄️  impure (nix-shell-env) 
❯ sudo nvme list
Node                  Generic               SN                   Model                                    Namespace  Usage                      Format           FW Rev  
--------------------- --------------------- -------------------- ---------------------------------------- ---------- -------------------------- ---------------- --------
/dev/nvme0n1          /dev/ng0n1            Z4HF716NF88S         KIOXIA-EXCERIA with Heatsink SSD         0x1          1.02  TB /   1.02  TB    512   B +  0 B   AJRA4101
/dev/nvme1n1          /dev/ng1n1            201008800819         WDC WD BLACK SDBPNTY-512G-1106           0x1        512.11  GB / 512.11  GB    512   B +  0 B   HPS2    
/dev/nvme2n1          /dev/ng2n1            TTSMA2513X09608      TWSC TSC3AN512-F8T40S                    0x1        512.11  GB / 512.11  GB    512   B +  0 B   SN13126 
```
