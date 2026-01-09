# BRAVEHEART ECG 數據處理完整流程說明

## 目錄
1. [概述](#概述)
2. [ECG 數據加載](#ecg-數據加載)
3. [基線校正 (Baseline Correction)](#基線校正-baseline-correction)
4. [濾波處理 (Filtering)](#濾波處理-filtering)
5. [完整處理管道](#完整處理管道)
6. [代碼示例](#代碼示例)

---

## 概述

BRAVEHEART 是一個用於心電圖 (ECG) 和向量心電圖 (VCG) 分析的開源軟件包。本文檔詳細說明從原始 ECG 數據加載到信號處理的完整流程。

### 主要處理步驟

```
原始 ECG 數據 → 加載 → 基線校正 → 濾波 → VCG 轉換 → 特徵提取 → 分析結果
```

---

## ECG 數據加載

### 支持的格式

BRAVEHEART 支持多種 ECG 格式，包括：
- **GE MUSE XML** - 醫療設備常用格式
- **Philips XML** - 飛利浦設備格式
- **DICOM** - 醫療影像標準格式
- **HL7 XML** - 醫療信息交換標準
- **SCP-ECG** - 歐洲標準格式
- **ISHNE** - 國際標準格式
- **EDF** - 歐洲數據格式
- 其他格式（見 README.md）

### 數據結構

ECG 數據通常包含 **12 導聯 (12-lead)**：

**肢體導聯 (Limb Leads)**：
- **I, II, III** - 雙極肢體導聯（測量兩個電極之間的電位差）
- **aVR, aVL, aVF** - 增強單極肢體導聯（augmented unipolar limb leads）

**胸前導聯 (Precordial Leads)**：
- **V1, V2, V3, V4, V5, V6** - 單極胸前導聯（測量心臟電活動的水平面）

### 加載流程詳解

#### 1. ECG12 類構造器

`ECG12.m` 是核心類，用於加載和存儲 12 導聯 ECG 數據。

```matlab
% 構造器調用示例
ecg = ECG12(filename, format);
```

**參數說明**：
- `filename`: ECG 文件的完整路徑
- `format`: 文件格式字符串（如 'muse_xml', 'dicom', 'hl7_xml' 等）

#### 2. 數據讀取過程

根據不同格式，系統會調用相應的加載函數：

```matlab
% 以 MUSE XML 為例
case 'muse_xml'
    [obj.hz, obj.I, obj.II, obj.V1, obj.V2, obj.V3, obj.V4, obj.V5, obj.V6] = ...
        load_musexml(filename);
    % 計算導聯關係（Einthoven's Law）
    obj.III = -obj.I + obj.II;        % III = II - I
    obj.avF = obj.II - 0.5*obj.I;     % aVF = (II + III) / 2
    obj.avR = -0.5*obj.I - 0.5*obj.II; % aVR = -(I + II) / 2
    obj.avL = obj.I - 0.5*obj.II;     % aVL = (I - III) / 2
```

**關鍵概念**：
- **採樣頻率 (hz)**: 通常為 250-1000 Hz，決定信號的時間分辨率
- **單位 (units)**: 通常為毫伏 (mV)
- **增益 (gain)**: 原始數字值到實際電壓的轉換係數

#### 3. 數據校驗

```matlab
% 確保所有導聯數據都成功加載
fn = fieldnames(ECG12());
for i = 3:length(fn)
    if isempty(obj.(fn{i}))
        error(sprintf('%s seems to be incorrect - could not find ECG data in file',format));
    end
end
```

---

## 基線校正 (Baseline Correction)

### 問題背景

ECG 信號在採集過程中常受到 **基線漂移 (Baseline Wander)** 的影響，主要原因包括：
1. **呼吸運動** - 呼吸引起的胸腔運動（頻率約 0.15-0.3 Hz）
2. **身體移動** - 患者或電極的移動
3. **電極接觸不良** - 皮膚-電極界面阻抗變化
4. **設備漂移** - 放大器直流漂移

### 技術實現：小波變換高通濾波

BRAVEHEART 使用 **離散小波變換 (DWT)** 進行基線校正。

#### 原理說明

小波變換可以將信號分解為不同頻率成分：
- **近似係數 (Approximation)**: 低頻成分（包含基線漂移）
- **細節係數 (Detail)**: 高頻成分（包含 ECG 特徵）

```
原始信號 = 近似信號 (低頻) + 細節信號 (高頻)
```

通過減去低頻近似信號，可以去除基線漂移。

#### 代碼實現：wander_remove.m

```matlab
function [signal_nowander, approx_signal, lvl] = wander_remove(freq, hr, signal, wavelet_name_lf, wavelet_level_lf)
% 基線漂移去除函數
% 
% 輸入參數:
%   freq - 採樣頻率 (Hz)
%   hr - 心率 (bpm, beats per minute)
%   signal - 輸入的 ECG 信號（已鏡像擴展以減少邊界效應）
%   wavelet_name_lf - 小波基函數名稱（如 'db6', 'sym8'）
%   wavelet_level_lf - 分解層數（0 表示自動選擇）
% 
% 輸出參數:
%   signal_nowander - 去除基線漂移後的信號
%   approx_signal - 提取的基線漂移成分
%   lvl - 使用的分解層數

% 1. 計算信號長度和最大分解層數
num_samples = length(signal)/3;  % 去除鏡像擴展的實際長度
max_lvl = floor(log2(num_samples));  % 最大層數 = log2(樣本數)

% 2. 執行小波分解
[A, D] = wavedec(signal, max_lvl, wavelet_name_lf);
% A: 近似係數向量
% D: 細節係數向量

% 3. 確定分解層數
if wavelet_level_lf > 0
    % 用戶指定層數
    n = wavelet_level_lf;
else
    % 自動計算：基於心率頻率
    freq_c = hr/60;  % 心率頻率 (Hz)
    % 選擇能去除所有低於心率頻率的層數
    n = ceil(log2((freq/2)/freq_c));
end

% 4. 重構近似信號（基線漂移成分）
approx_signal = wrcoef('a', A, D, wavelet_name_lf, n);

% 5. 從原始信號中減去基線漂移
signal_nowander = signal - approx_signal;
lvl = n;
```

**層數選擇指南**：
- **層數越高，截止頻率越低**
- 典型值：8-10 層（對應呼吸頻率範圍）
- 對於 500 Hz 採樣率：
  - 層數 8: 截止頻率 ≈ 1.95 Hz
  - 層數 9: 截止頻率 ≈ 0.98 Hz
  - 層數 10: 截止頻率 ≈ 0.49 Hz

#### 邊界效應處理：鏡像擴展

為了減少小波變換的邊界效應，使用 `mirror()` 函數：

```matlab
% mirror.m 的實現概念
% 將信號前後各擴展一倍長度，使用鏡像對稱
% 
% 原始信號: [a, b, c, d, e]
% 鏡像擴展: [e, d, c, b, a, | a, b, c, d, e | e, d, c, b, a]
%                           ↑ 原始部分 ↑

% 處理後使用 middlethird() 提取中間部分（原始信號）
```

---

## 濾波處理 (Filtering)

### 濾波目的

ECG 信號除了基線漂移，還受到多種高頻噪聲干擾：
1. **肌電干擾 (EMG)** - 頻率 > 30 Hz
2. **工頻干擾** - 50/60 Hz 電源線
3. **高頻電子噪聲** - 儀器設備產生

### 兩階段濾波策略

BRAVEHEART 採用兩階段濾波：

#### 1. 低頻濾波（高通濾波）- 去除基線漂移

```matlab
% 在 ecgfilter.m 中的低頻濾波部分
if wavelet_filt_lf == 1
    % 對每個導聯進行處理
    [L1, aL1, lvl_L1] = wander_remove(freq, maxRR_hr, mirror(L1), wavelet_name_lf, wavelet_level_lf);
    L1 = middlethird(L1);  % 提取中間有效部分
    
    % ... 對其他導聯重複相同操作
end
```

**參數說明**：
- `wavelet_filt_lf`: 布爾標誌，是否啟用低頻濾波
- `wavelet_name_lf`: 小波基函數（推薦 'db6' 或 'sym8'）
- `wavelet_level_lf`: 分解層數

#### 2. 高頻濾波（低通濾波）- 去除高頻噪聲

```matlab
% 在 ecgfilter.m 中的高頻濾波部分
if wavelet_filt == 1
    % 使用 MATLAB 內建的小波去噪函數
    L1 = wden(L1, 'modwtsqtwolog', 's', 'mln', wavelet_level, wavelet_name);
    
    % wden 參數說明:
    % - 'modwtsqtwolog': 閾值選擇方法（最大重疊離散小波變換 + 通用閾值）
    % - 's': 軟閾值（soft thresholding）
    % - 'mln': 多層噪聲估計
    % - wavelet_level: 分解層數
    % - wavelet_name: 小波基函數
    
    % ... 對其他導聯重複相同操作
end
```

**閾值方法比較**：

| 方法 | 特點 | 適用場景 |
|------|------|----------|
| 軟閾值 (Soft) | 連續性好，可能過度平滑 | ECG 信號處理 |
| 硬閾值 (Hard) | 保留更多細節，可能有不連續 | 需要保留尖銳特徵 |

### 完整濾波函數：ecgfilter.m

```matlab
function [L1, L2, L3, avR, avF, avL, V1, V2, V3, V4, V5, V6, final_lf_wavelet_lvl_min] = ...
    ecgfilter(L1, L2, L3, avR, avF, avL, V1, V2, V3, V4, V5, V6, freq, maxRR_hr, ...
    wavelet_filt, wavelet_level, wavelet_name, wavelet_filt_lf, wavelet_level_lf, wavelet_name_lf)
% ECG 濾波主函數
%
% 輸入參數:
%   L1-V6: 12 個導聯的信號數據
%   freq: 採樣頻率
%   maxRR_hr: 最大 RR 間期對應的心率（用於自動確定高通濾波截止頻率）
%   wavelet_filt: 是否進行高頻濾波 (1=是, 0=否)
%   wavelet_level: 高頻濾波的小波分解層數
%   wavelet_name: 高頻濾波的小波基函數
%   wavelet_filt_lf: 是否進行低頻濾波 (1=是, 0=否)
%   wavelet_level_lf: 低頻濾波的小波分解層數
%   wavelet_name_lf: 低頻濾波的小波基函數
%
% 輸出參數:
%   L1-V6: 濾波後的 12 個導聯信號
%   final_lf_wavelet_lvl_min: 實際使用的低頻濾波層數

final_lf_wavelet_lvl_min = 'N/A';

% === 第一階段：低頻濾波（去除基線漂移）===
if wavelet_filt_lf == 1
    % 處理肢體導聯
    [L1, aL1, lvl_L1] = wander_remove(freq, maxRR_hr, mirror(L1), wavelet_name_lf, wavelet_level_lf);
    [L2, aL2, lvl_L2] = wander_remove(freq, maxRR_hr, mirror(L2), wavelet_name_lf, wavelet_level_lf);
    [L3, aL3, lvl_L3] = wander_remove(freq, maxRR_hr, mirror(L3), wavelet_name_lf, wavelet_level_lf);
    
    % 提取中間三分之一（去除鏡像擴展的邊界部分）
    L1 = middlethird(L1);
    L2 = middlethird(L2);
    L3 = middlethird(L3);
    
    % 處理增強肢體導聯
    [avR, aavR, lvl_avR] = wander_remove(freq, maxRR_hr, mirror(avR), wavelet_name_lf, wavelet_level_lf);
    [avL, aavL, lvl_avL] = wander_remove(freq, maxRR_hr, mirror(avL), wavelet_name_lf, wavelet_level_lf);
    [avF, aavF, lvl_avF] = wander_remove(freq, maxRR_hr, mirror(avF), wavelet_name_lf, wavelet_level_lf);
    
    avR = middlethird(avR);
    avL = middlethird(avL);
    avF = middlethird(avF);
    
    % 處理胸前導聯
    [V1, aV1, lvl_V1] = wander_remove(freq, maxRR_hr, mirror(V1), wavelet_name_lf, wavelet_level_lf);
    [V2, aV2, lvl_V2] = wander_remove(freq, maxRR_hr, mirror(V2), wavelet_name_lf, wavelet_level_lf);
    [V3, aV3, lvl_V3] = wander_remove(freq, maxRR_hr, mirror(V3), wavelet_name_lf, wavelet_level_lf);
    [V4, aV4, lvl_V4] = wander_remove(freq, maxRR_hr, mirror(V4), wavelet_name_lf, wavelet_level_lf);
    [V5, aV5, lvl_V5] = wander_remove(freq, maxRR_hr, mirror(V5), wavelet_name_lf, wavelet_level_lf);
    [V6, aV6, lvl_V6] = wander_remove(freq, maxRR_hr, mirror(V6), wavelet_name_lf, wavelet_level_lf);
    
    V1 = middlethird(V1);
    V2 = middlethird(V2);
    V3 = middlethird(V3);
    V4 = middlethird(V4);
    V5 = middlethird(V5);
    V6 = middlethird(V6);
    
    final_lf_wavelet_lvl_min = lvl_L1;
end

% === 第二階段：高頻濾波（去除高頻噪聲）===
if wavelet_filt == 1
    % 對所有導聯應用小波去噪
    L1 = wden(L1, 'modwtsqtwolog', 's', 'mln', wavelet_level, wavelet_name);
    L2 = wden(L2, 'modwtsqtwolog', 's', 'mln', wavelet_level, wavelet_name);
    L3 = wden(L3, 'modwtsqtwolog', 's', 'mln', wavelet_level, wavelet_name);
    avR = wden(avR, 'modwtsqtwolog', 's', 'mln', wavelet_level, wavelet_name);
    avL = wden(avL, 'modwtsqtwolog', 's', 'mln', wavelet_level, wavelet_name);
    avF = wden(avF, 'modwtsqtwolog', 's', 'mln', wavelet_level, wavelet_name);
    V1 = wden(V1, 'modwtsqtwolog', 's', 'mln', wavelet_level, wavelet_name);
    V2 = wden(V2, 'modwtsqtwolog', 's', 'mln', wavelet_level, wavelet_name);
    V3 = wden(V3, 'modwtsqtwolog', 's', 'mln', wavelet_level, wavelet_name);
    V4 = wden(V4, 'modwtsqtwolog', 's', 'mln', wavelet_level, wavelet_name);
    V5 = wden(V5, 'modwtsqtwolog', 's', 'mln', wavelet_level, wavelet_name);
    V6 = wden(V6, 'modwtsqtwolog', 's', 'mln', wavelet_level, wavelet_name);
end

end
```

---

## 完整處理管道

### 步驟 1: 加載 ECG 數據

```matlab
% 創建 ECG12 對象
filename = 'patient_001.xml';
format = 'muse_xml';
ecg = ECG12(filename, format);

% ecg 對象現在包含:
% - ecg.hz: 採樣頻率
% - ecg.I, ecg.II, ecg.III: 肢體導聯
% - ecg.avR, ecg.avL, ecg.avF: 增強肢體導聯
% - ecg.V1 - ecg.V6: 胸前導聯
```

### 步驟 2: 設置處理參數

```matlab
% 創建註釋參數對象
aps = Annoparams();

% 設置濾波參數
aps.highpass = 1;                    % 啟用高通濾波（去基線漂移）
aps.wavelet_level_highpass = 9;      % 高通濾波層數
aps.wavelet_name_highpass = 'db6';   % 高通濾波小波基

aps.lowpass = 1;                     % 啟用低通濾波（去高頻噪聲）
aps.wavelet_level_lowpass = 6;       % 低通濾波層數
aps.wavelet_name_lowpass = 'db6';    % 低通濾波小波基

% 設置轉換矩陣（ECG 到 VCG）
aps.transform_matrix_str = 'Kors';   % 使用 Kors 轉換矩陣
```

### 步驟 3: 執行濾波

```matlab
% 估計最大 RR 間期對應的心率（用於自動頻率選擇）
maxRR_hr = 60;  % 假設最慢心率為 60 bpm

% 應用濾波
[filtered_ecg, highpass_lvl_min] = ecg.filter(maxRR_hr, aps);

% filtered_ecg 現在包含濾波後的信號
% highpass_lvl_min 是實際使用的高通濾波層數
```

### 步驟 4: 轉換為 VCG（可選）

```matlab
% 從 12 導聯 ECG 創建 VCG 對象
vcg = VCG(filtered_ecg, aps);

% vcg 對象包含:
% - vcg.X: X 軸向量（左-右）
% - vcg.Y: Y 軸向量（頭-腳）
% - vcg.Z: Z 軸向量（前-後）
% - vcg.VM: 向量幅度 = sqrt(X^2 + Y^2 + Z^2)
```

### 步驟 5: 檢測 QRS 波群

```matlab
% 檢測 R 波峰值
QRS = vcg.peaks(aps);

% QRS 是包含所有檢測到的 R 波位置的數組（以樣本點為單位）
```

### 步驟 6: 生成中位數心搏

```matlab
% 計算中位數心搏（median beat）
[medianbeat_vcg, beatsig_vcg] = vcg.medianbeat(QRS-200, QRS+400);

% medianbeat_vcg: 中位數心搏的 VCG 對象
% beatsig_vcg: 所有對齊心搏的集合
```

---

## 代碼示例

### 完整示例：從加載到處理

```matlab
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% BRAVEHEART ECG 處理完整示例
% 功能：加載 ECG 數據並執行基線校正和濾波
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% 1. 初始化和加載數據
clear; clc;

% 設置文件路徑
ecg_file = 'example_ecg.xml';  % 替換為您的 ECG 文件路徑
ecg_format = 'muse_xml';       % 根據實際格式修改

% 加載 ECG 數據
fprintf('正在加載 ECG 數據...\n');
ecg = ECG12(ecg_file, ecg_format);
fprintf('加載完成！採樣頻率: %d Hz\n', ecg.hz);

%% 2. 查看原始信號
figure('Name', '原始 ECG 信號');

% 計算時間軸
t = (0:length(ecg.I)-1) / ecg.hz;  % 時間（秒）

% 繪製部分導聯
subplot(3,1,1); plot(t, ecg.I); 
title('導聯 I (原始)'); ylabel('電壓 (mV)'); grid on;

subplot(3,1,2); plot(t, ecg.II); 
title('導聯 II (原始)'); ylabel('電壓 (mV)'); grid on;

subplot(3,1,3); plot(t, ecg.V1); 
title('導聯 V1 (原始)'); xlabel('時間 (秒)'); ylabel('電壓 (mV)'); grid on;

%% 3. 設置處理參數
aps = Annoparams();

% === 基線校正參數 ===
aps.highpass = 1;                    % 啟用高通濾波
aps.wavelet_level_highpass = 9;      % 層數：9（適合去除呼吸漂移）
aps.wavelet_name_highpass = 'db6';   % 小波：Daubechies 6

% === 高頻去噪參數 ===
aps.lowpass = 1;                     % 啟用低通濾波
aps.wavelet_level_lowpass = 6;       % 層數：6（適合去除肌電干擾）
aps.wavelet_name_lowpass = 'db6';    % 小波：Daubechies 6

% === 其他參數 ===
aps.transform_matrix_str = 'Kors';   % VCG 轉換矩陣
aps.maxBPM = 200;                    % 最大心率（用於 R 波檢測）

fprintf('\n處理參數:\n');
fprintf('  高通濾波: %s (層數=%d, 小波=%s)\n', ...
    mat2str(aps.highpass), aps.wavelet_level_highpass, aps.wavelet_name_highpass);
fprintf('  低通濾波: %s (層數=%d, 小波=%s)\n', ...
    mat2str(aps.lowpass), aps.wavelet_level_lowpass, aps.wavelet_name_lowpass);

%% 4. 執行濾波處理
fprintf('\n正在執行濾波處理...\n');

% 估計最大 RR 間期心率
maxRR_hr = 60;  % bpm（每分鐘心跳數）

% 應用濾波
[filtered_ecg, highpass_lvl_used] = ecg.filter(maxRR_hr, aps);

fprintf('濾波完成！實際使用的高通濾波層數: %s\n', mat2str(highpass_lvl_used));

%% 5. 查看濾波後信號
figure('Name', '濾波後 ECG 信號');

% 繪製濾波後的導聯
subplot(3,1,1); plot(t, filtered_ecg.I); 
title('導聯 I (濾波後)'); ylabel('電壓 (mV)'); grid on;

subplot(3,1,2); plot(t, filtered_ecg.II); 
title('導聯 II (濾波後)'); ylabel('電壓 (mV)'); grid on;

subplot(3,1,3); plot(t, filtered_ecg.V1); 
title('導聯 V1 (濾波後)'); xlabel('時間 (秒)'); ylabel('電壓 (mV)'); grid on;

%% 6. 對比原始和濾波後的信號
figure('Name', '濾波效果對比');

% 選擇一段代表性區間（例如前 5 秒）
sample_range = 1:min(5*ecg.hz, length(ecg.I));
t_sample = t(sample_range);

% 導聯 II 對比
subplot(2,1,1);
plot(t_sample, ecg.II(sample_range), 'b', 'LineWidth', 1);
hold on;
plot(t_sample, filtered_ecg.II(sample_range), 'r', 'LineWidth', 1.5);
legend('原始信號', '濾波後信號');
title('導聯 II 對比');
ylabel('電壓 (mV)'); grid on;

% 導聯 V1 對比
subplot(2,1,2);
plot(t_sample, ecg.V1(sample_range), 'b', 'LineWidth', 1);
hold on;
plot(t_sample, filtered_ecg.V1(sample_range), 'r', 'LineWidth', 1.5);
legend('原始信號', '濾波後信號');
title('導聯 V1 對比');
xlabel('時間 (秒)'); ylabel('電壓 (mV)'); grid on;

%% 7. 轉換為 VCG 並分析
fprintf('\n正在生成 VCG...\n');
vcg = VCG(filtered_ecg, aps);

% 計算 VM (Vector Magnitude)
% VM 是 X, Y, Z 三個分量的向量和: VM = sqrt(X^2 + Y^2 + Z^2)
figure('Name', 'VCG 信號');

subplot(4,1,1); plot(t, vcg.X); 
title('VCG X 軸 (左-右)'); ylabel('電壓 (mV)'); grid on;

subplot(4,1,2); plot(t, vcg.Y); 
title('VCG Y 軸 (頭-腳)'); ylabel('電壓 (mV)'); grid on;

subplot(4,1,3); plot(t, vcg.Z); 
title('VCG Z 軸 (前-後)'); ylabel('電壓 (mV)'); grid on;

subplot(4,1,4); plot(t, vcg.VM, 'k', 'LineWidth', 1.5); 
title('VCG 向量幅度 (VM)'); xlabel('時間 (秒)'); ylabel('電壓 (mV)'); grid on;

%% 8. 檢測 R 波峰值
fprintf('正在檢測 R 波...\n');
QRS_locations = vcg.peaks(aps);

% 計算心率
if length(QRS_locations) > 1
    % RR 間期（以秒為單位）
    RR_intervals = diff(QRS_locations) / vcg.hz;
    % 平均心率
    avg_heart_rate = 60 / mean(RR_intervals);
    fprintf('檢測到 %d 個心搏，平均心率: %.1f bpm\n', ...
        length(QRS_locations), avg_heart_rate);
else
    fprintf('檢測到的心搏數量不足\n');
end

% 在 VM 信號上標記 R 波位置
figure('Name', 'R 波檢測結果');
plot(t, vcg.VM, 'b'); hold on;
plot(t(QRS_locations), vcg.VM(QRS_locations), 'ro', 'MarkerSize', 8, 'LineWidth', 2);
title('R 波檢測結果（標記在 VCG VM 上）');
xlabel('時間 (秒)'); ylabel('電壓 (mV)');
legend('VCG VM', 'R 波位置');
grid on;

%% 9. 生成中位數心搏
if length(QRS_locations) > 1
    fprintf('正在生成中位數心搏...\n');
    
    % 定義心搏窗口（R 波前 200ms 到 R 波後 400ms）
    pre_samples = round(0.2 * vcg.hz);   % 200ms 前
    post_samples = round(0.4 * vcg.hz);  % 400ms 後
    
    % 生成中位數心搏
    [medianbeat_vcg, beatsig_vcg] = vcg.medianbeat(...
        QRS_locations - pre_samples, ...
        QRS_locations + post_samples);
    
    % 繪製中位數心搏
    beat_length = length(medianbeat_vcg.VM);
    beat_time = (0:beat_length-1) / vcg.hz * 1000;  % 轉換為毫秒
    
    figure('Name', '中位數心搏');
    
    subplot(4,1,1); plot(beat_time, medianbeat_vcg.X);
    title('中位數心搏 - X 軸'); ylabel('電壓 (mV)'); grid on;
    
    subplot(4,1,2); plot(beat_time, medianbeat_vcg.Y);
    title('中位數心搏 - Y 軸'); ylabel('電壓 (mV)'); grid on;
    
    subplot(4,1,3); plot(beat_time, medianbeat_vcg.Z);
    title('中位數心搏 - Z 軸'); ylabel('電壓 (mV)'); grid on;
    
    subplot(4,1,4); plot(beat_time, medianbeat_vcg.VM, 'k', 'LineWidth', 2);
    title('中位數心搏 - VM'); xlabel('時間 (ms)'); ylabel('電壓 (mV)'); grid on;
    
    fprintf('中位數心搏生成完成！\n');
end

%% 10. 總結
fprintf('\n=== 處理完成總結 ===\n');
fprintf('輸入文件: %s\n', ecg_file);
fprintf('採樣頻率: %d Hz\n', ecg.hz);
fprintf('信號長度: %.2f 秒\n', length(ecg.I)/ecg.hz);
fprintf('處理步驟:\n');
fprintf('  1. 基線校正 (高通濾波)\n');
fprintf('  2. 高頻去噪 (低通濾波)\n');
fprintf('  3. ECG 到 VCG 轉換\n');
fprintf('  4. R 波檢測\n');
fprintf('  5. 中位數心搏生成\n');
fprintf('=====================\n');
```

### 自定義基線校正示例

```matlab
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 自定義基線校正處理示例
% 演示如何手動執行基線校正步驟
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% 準備數據
clear; clc;

% 假設已經有一個 ECG 信號向量
% 這裡我們創建一個模擬信號用於演示
fs = 500;  % 採樣頻率 (Hz)
t = 0:1/fs:10;  % 10 秒數據

% 生成模擬 ECG 信號（簡化的 QRS 波形）
ecg_clean = zeros(size(t));
for i = 1:5  % 5 個心搏
    peak_loc = i * fs * 2;  % 每 2 秒一個峰值
    if peak_loc <= length(t)
        % 簡化的 QRS 複合波
        qrs_width = round(0.1 * fs);  % QRS 寬度約 100ms
        qrs_range = max(1, peak_loc-qrs_width):min(length(t), peak_loc+qrs_width);
        ecg_clean(qrs_range) = 1.0 * exp(-((qrs_range-peak_loc).^2)/(2*(qrs_width/3)^2));
    end
end

% 添加基線漂移（模擬呼吸）
baseline_drift = 0.3 * sin(2*pi*0.2*t);  % 0.2 Hz 呼吸頻率

% 添加高頻噪聲
high_freq_noise = 0.05 * randn(size(t));

% 組合信號
ecg_noisy = ecg_clean + baseline_drift + high_freq_noise;

%% 執行基線校正
fprintf('執行基線校正...\n');

% 參數設置
wavelet_name = 'db6';      % Daubechies 6 小波
wavelet_level = 9;         % 分解層數
heart_rate = 60;           % 心率 (bpm)

% 使用 mirror 函數進行鏡像擴展（減少邊界效應）
ecg_mirrored = mirror(ecg_noisy);

% 執行基線去除
[ecg_corrected_full, baseline_estimated, level_used] = ...
    wander_remove(fs, heart_rate, ecg_mirrored, wavelet_name, wavelet_level);

% 提取中間部分（去除鏡像）
ecg_corrected = middlethird(ecg_corrected_full);

fprintf('基線校正完成！使用層數: %d\n', level_used);

%% 可視化結果
figure('Name', '基線校正詳細過程');

% 子圖 1: 原始乾淨信號
subplot(5,1,1);
plot(t, ecg_clean, 'k', 'LineWidth', 1);
title('1. 原始乾淨 ECG 信號（無噪聲）');
ylabel('電壓 (mV)'); grid on;
ylim([-0.5, 1.5]);

% 子圖 2: 基線漂移
subplot(5,1,2);
plot(t, baseline_drift, 'r', 'LineWidth', 1);
title('2. 基線漂移成分（呼吸影響）');
ylabel('電壓 (mV)'); grid on;

% 子圖 3: 加噪聲後的信號
subplot(5,1,3);
plot(t, ecg_noisy, 'b', 'LineWidth', 1);
title('3. 含噪聲的 ECG 信號（原始 + 基線漂移 + 高頻噪聲）');
ylabel('電壓 (mV)'); grid on;
ylim([-0.5, 1.5]);

% 子圖 4: 估計的基線
subplot(5,1,4);
baseline_estimated_trimmed = middlethird(baseline_estimated);
plot(t, baseline_estimated_trimmed, 'g', 'LineWidth', 1.5);
title('4. 估計的基線漂移（小波分解提取）');
ylabel('電壓 (mV)'); grid on;

% 子圖 5: 校正後的信號
subplot(5,1,5);
plot(t, ecg_corrected, 'b', 'LineWidth', 1);
hold on;
plot(t, ecg_clean, 'k--', 'LineWidth', 1);
title('5. 基線校正後的信號（藍色）vs. 原始乾淨信號（黑虛線）');
xlabel('時間 (秒)'); ylabel('電壓 (mV)');
legend('校正後', '原始乾淨');
grid on;
ylim([-0.5, 1.5]);

%% 分析校正效果
% 計算誤差
error_before = ecg_noisy - ecg_clean;
error_after = ecg_corrected - ecg_clean;

fprintf('\n校正效果分析:\n');
fprintf('  校正前 RMS 誤差: %.4f mV\n', rms(error_before));
fprintf('  校正後 RMS 誤差: %.4f mV\n', rms(error_after));
fprintf('  誤差減少: %.2f%%\n', (1 - rms(error_after)/rms(error_before)) * 100);

%% 頻譜分析
figure('Name', '頻譜分析');

% 計算 FFT
N = length(ecg_noisy);
freq_axis = (0:N-1) * (fs/N);

fft_noisy = abs(fft(ecg_noisy));
fft_corrected = abs(fft(ecg_corrected));

% 只顯示前半部分（Nyquist 頻率以下）
half_N = floor(N/2);

subplot(2,1,1);
plot(freq_axis(1:half_N), fft_noisy(1:half_N), 'b');
title('校正前 - 頻譜');
xlabel('頻率 (Hz)'); ylabel('幅度'); grid on;
xlim([0, 50]);  % 顯示 0-50 Hz

subplot(2,1,2);
plot(freq_axis(1:half_N), fft_corrected(1:half_N), 'r');
title('校正後 - 頻譜（低頻成分減少）');
xlabel('頻率 (Hz)'); ylabel('幅度'); grid on;
xlim([0, 50]);

fprintf('\n注意: 校正後的頻譜在低頻區域（< 0.5 Hz）能量顯著降低\n');
```

### 參數調優指南

```matlab
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% ECG 濾波參數調優指南
% 幫助選擇最佳的濾波參數
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% 測試不同的小波分解層數
clear; clc;

% 假設已加載 ECG 數據
% ecg = ECG12('your_file.xml', 'muse_xml');

% 測試參數範圍
test_levels = 7:11;  % 測試層數 7 到 11
wavelet_name = 'db6';
fs = 500;  % 假設採樣頻率
heart_rate = 60;

% 創建一個測試信號（實際應用中替換為真實 ECG）
t = 0:1/fs:10;
test_signal = sin(2*pi*1*t) + 0.5*sin(2*pi*0.1*t) + 0.1*randn(size(t));

figure('Name', '不同層數的濾波效果');
for i = 1:length(test_levels)
    level = test_levels(i);
    
    % 執行濾波
    [filtered, baseline, ~] = wander_remove(fs, heart_rate, ...
        mirror(test_signal), wavelet_name, level);
    filtered = middlethird(filtered);
    
    % 繪製結果
    subplot(length(test_levels), 1, i);
    plot(t, filtered);
    title(sprintf('層數 = %d (截止頻率 ≈ %.2f Hz)', ...
        level, (fs/2)/(2^level)));
    ylabel('電壓 (mV)');
    if i == length(test_levels)
        xlabel('時間 (秒)');
    end
    grid on;
end

%% 小波基函數比較
wavelet_families = {'db4', 'db6', 'db8', 'sym4', 'sym8', 'coif4'};

fprintf('\n常用小波基函數特性:\n');
fprintf('%-10s %-20s %-30s\n', '名稱', '全稱', '特點');
fprintf('%s\n', repmat('-', 1, 60));
fprintf('%-10s %-20s %-30s\n', 'db4', 'Daubechies 4', '緊支撐，適度平滑');
fprintf('%-10s %-20s %-30s\n', 'db6', 'Daubechies 6', '平衡性能，推薦用於 ECG');
fprintf('%-10s %-20s %-30s\n', 'db8', 'Daubechies 8', '更平滑，計算量稍大');
fprintf('%-10s %-20s %-30s\n', 'sym4', 'Symlet 4', '近似對稱，減少相位失真');
fprintf('%-10s %-20s %-30s\n', 'sym8', 'Symlet 8', '對稱性好，適合保留特徵');
fprintf('%-10s %-20s %-30s\n', 'coif4', 'Coiflet 4', '對稱性最好，計算量大');

%% 推薦參數組合
fprintf('\n=== 推薦參數組合 ===\n\n');

fprintf('【方案 1】標準處理（推薦用於大多數情況）\n');
fprintf('  基線校正:\n');
fprintf('    - 小波: db6\n');
fprintf('    - 層數: 9\n');
fprintf('    - 截止頻率: 約 0.98 Hz @ 500 Hz 採樣\n');
fprintf('  高頻去噪:\n');
fprintf('    - 小波: db6\n');
fprintf('    - 層數: 6\n');
fprintf('  適用: 常規 ECG，輕度到中度噪聲\n\n');

fprintf('【方案 2】強基線校正（用於嚴重基線漂移）\n');
fprintf('  基線校正:\n');
fprintf('    - 小波: sym8\n');
fprintf('    - 層數: 10\n');
fprintf('    - 截止頻率: 約 0.49 Hz @ 500 Hz 採樣\n');
fprintf('  高頻去噪:\n');
fprintf('    - 小波: sym8\n');
fprintf('    - 層數: 7\n');
fprintf('  適用: 明顯呼吸運動，患者移動較多\n\n');

fprintf('【方案 3】輕度處理（保留更多原始特徵）\n');
fprintf('  基線校正:\n');
fprintf('    - 小波: db6\n');
fprintf('    - 層數: 8\n');
fprintf('    - 截止頻率: 約 1.95 Hz @ 500 Hz 採樣\n');
fprintf('  高頻去噪:\n');
fprintf('    - 小波: db4\n');
fprintf('    - 層數: 5\n');
fprintf('  適用: 高質量 ECG，需要精確特徵分析\n\n');

fprintf('【方案 4】激進去噪（用於低質量信號）\n');
fprintf('  基線校正:\n');
fprintf('    - 小波: sym8\n');
fprintf('    - 層數: 10\n');
fprintf('  高頻去噪:\n');
fprintf('    - 小波: coif4\n');
fprintf('    - 層數: 8\n');
fprintf('  適用: 嚴重肌電干擾，運動偽影多\n');
fprintf('  注意: 可能過度平滑，損失部分細節\n\n');

%% 質量評估指標
fprintf('=== 濾波質量評估指標 ===\n\n');

fprintf('1. 基線穩定性:\n');
fprintf('   - 測量 TP 段（T 波結束到 P 波開始）的標準差\n');
fprintf('   - 目標: < 0.05 mV\n\n');

fprintf('2. QRS 波形保真度:\n');
fprintf('   - 比較濾波前後 QRS 寬度和幅度\n');
fprintf('   - 變化應 < 5%%\n\n');

fprintf('3. T 波形態:\n');
fprintf('   - T 波應平滑但不過度鈍化\n');
fprintf('   - 避免引入偽差\n\n');

fprintf('4. 信噪比 (SNR):\n');
fprintf('   - SNR = 10 * log10(信號功率 / 噪聲功率)\n');
fprintf('   - 目標: > 20 dB\n\n');
```

---

## 技術細節和最佳實踐

### 1. 採樣頻率考慮

不同採樣頻率需要調整參數：

| 採樣頻率 | 推薦基線校正層數 | 截止頻率 (Hz) |
|----------|------------------|---------------|
| 250 Hz   | 8                | 0.98          |
| 500 Hz   | 9                | 0.98          |
| 1000 Hz  | 10               | 0.98          |

### 2. 信號質量預處理

```matlab
% 檢查信號質量
function quality_score = assess_signal_quality(ecg_signal, fs)
    % 1. 檢查飽和（信號削波）
    max_val = max(abs(ecg_signal));
    if max_val > 5.0  % mV
        warning('信號可能飽和');
    end
    
    % 2. 檢查基線漂移程度
    baseline_std = std(ecg_signal);
    if baseline_std > 1.0
        warning('基線漂移嚴重');
    end
    
    % 3. 檢查缺失數據
    if any(isnan(ecg_signal)) || any(isinf(ecg_signal))
        error('信號包含 NaN 或 Inf 值');
    end
    
    % 簡單的質量評分（0-100）
    quality_score = 100 - min(baseline_std*20, 50);
end
```

### 3. 常見問題和解決方案

#### 問題 1: 過度濾波導致 QRS 波形失真

**症狀**: QRS 波群變鈍，幅度降低

**解決方案**:
- 降低高頻濾波層數（從 7 降到 5-6）
- 更換小波基（使用 db4 而非 db8）
- 檢查是否誤用了錯誤的濾波參數

#### 問題 2: 基線仍然不穩定

**症狀**: TP 段仍有明顯波動

**解決方案**:
- 增加基線校正層數（從 9 增到 10-11）
- 使用更對稱的小波（sym8 或 coif4）
- 考慮多次迭代濾波

#### 問題 3: 濾波引入偽差

**症狀**: 濾波後出現原始信號沒有的波形

**解決方案**:
- 使用鏡像擴展（mirror 函數）減少邊界效應
- 檢查小波層數是否過高
- 驗證信號長度足夠（至少 2-3 秒）

### 4. 性能優化建議

```matlab
% 批量處理多個導聯時使用並行計算
parfor i = 1:12
    % 處理每個導聯
end

% 對於超長記錄（> 1 小時），考慮分段處理
segment_length = 10 * fs;  % 10 秒片段
for i = 1:segment_length:length(signal)
    segment = signal(i:min(i+segment_length-1, end));
    % 處理片段
end
```

---

## 附錄

### A. 小波變換數學基礎

小波變換將信號分解為不同尺度的小波係數：

```
WT(a, b) = ∫ signal(t) * ψ((t-b)/a) dt
```

其中：
- `a`: 尺度參數（控制小波的伸縮）
- `b`: 位移參數（控制小波的平移）
- `ψ`: 小波基函數

### B. 相關 MATLAB 函數

| 函數 | 用途 |
|------|------|
| `wavedec` | 離散小波分解 |
| `wrcoef` | 小波重構 |
| `wden` | 小波去噪 |
| `dwt` | 單層小波變換 |
| `idwt` | 單層小波逆變換 |

### C. 參考文獻

1. Stabenau HF, Waks JW. "BRAVEHEART: Open-source software for automated electrocardiographic and vectorcardiographic analysis." *Computer Methods and Programs in Biomedicine*, 2023.

2. Sörnmo L, Laguna P. "Bioelectrical Signal Processing in Cardiac and Neurological Applications." *Elsevier*, 2005.

3. Mallat S. "A Wavelet Tour of Signal Processing." *Academic Press*, 2009.

---

## 總結

本文檔詳細介紹了 BRAVEHEART 中的 ECG 數據處理流程：

1. **數據加載**: 支持多種格式，自動處理導聯關係
2. **基線校正**: 使用小波變換高通濾波去除低頻漂移
3. **高頻去噪**: 使用小波閾值去噪去除肌電等干擾
4. **完整管道**: 從原始數據到可分析的乾淨信號

關鍵技術點：
- 小波分解層數決定頻率特性
- 鏡像擴展減少邊界效應
- 不同場景需要不同參數組合

希望這份文檔能幫助您理解和使用 BRAVEHEART 進行 ECG 信號處理！
