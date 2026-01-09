%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% BRAVEHEART - 心電圖和向量心電圖分析開源軟件
% example_ecg_processing_workflow_zh.m -- ECG 數據處理完整工作流程示例（中文註解版）
% Copyright 2016-2025 Hans F. Stabenau and Jonathan W. Waks
% 
% 源代碼/可執行文件: https://github.com/BIVectors/BRAVEHEART
% 聯繫: braveheart.ecg@gmail.com
% 
% BRAVEHEART 是自由軟件: 您可以根據自由軟件基金會發布的 GNU 通用公共許可證
% 第 3 版或（根據您的選擇）任何更高版本的條款重新分發和/或修改它。
%
% BRAVEHEART 的發布是希望它有用，但不提供任何保證；
% 甚至不提供適銷性或特定用途適用性的默示保證。
% 有關更多詳細信息，請參閱 GNU 通用公共許可證。
% 
% 您應該已經收到了 GNU 通用公共許可證的副本。
% 如果沒有，請參閱 <https://www.gnu.org/licenses/>。
%
% 此軟件僅用於研究目的，不用於診斷或治療任何疾病。
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% ========== 工作流程概述 ==========
% 
% 本示例展示 BRAVEHEART 的完整 ECG 處理流程：
%
% 1. 加載 ECG 數據 (Load ECG Data)
%    └─ 從各種格式（XML, DICOM, etc.）讀取 12 導聯 ECG
%
% 2. 數據預處理 (Data Preprocessing)
%    ├─ 基線校正 (Baseline Correction)
%    │   └─ 使用小波變換高通濾波去除低頻漂移
%    └─ 高頻去噪 (High-frequency Denoising)
%        └─ 使用小波閾值去噪去除肌電干擾
%
% 3. 坐標變換 (Coordinate Transformation)
%    └─ 12 導聯 ECG → 3 軸向量心電圖 (VCG)
%
% 4. 特徵提取 (Feature Extraction)
%    ├─ R 波檢測 (R-peak Detection)
%    ├─ 生成中位數心搏 (Median Beat Generation)
%    └─ 標註基準點 (Fiducial Point Annotation)
%
% 5. 計算和分析 (Calculation and Analysis)
%    └─ 提取臨床參數（QT 間期、QRS 寬度等）

%% ========== 清理工作空間 ==========
clear all;      % 清除所有變量
close all;      % 關閉所有圖形窗口
clc;            % 清除命令窗口

%% ========== 第 1 步：加載 ECG 數據 ==========
fprintf('\n==========================================\n');
fprintf('步驟 1: 加載 ECG 數據\n');
fprintf('==========================================\n');

% 設置文件路徑和格式
% 注意：請根據您的實際文件修改以下路徑和格式
% 示例文件可以從 'Example ECGs' 目錄中選擇
ecg_filename = 'example_ecg.xml';  % ECG 文件名（請修改為實際文件路徑）
ecg_format = 'muse_xml';           % 文件格式

% 檢查文件是否存在
if ~exist(ecg_filename, 'file')
    error(['錯誤：文件不存在: %s\n\n' ...
           '請修改 ecg_filename 變量指向您的實際 ECG 文件。\n' ...
           '您可以使用 BRAVEHEART 的 ''Example ECGs'' 目錄中的示例文件。'], ...
           ecg_filename);
end

% 支持的格式列表：
% - 'muse_xml'      : GE MUSE XML 格式
% - 'philips_xml'   : Philips XML 格式
% - 'hl7_xml'       : HL7 XML 格式
% - 'dicom'         : DICOM 格式
% - 'scp_ecg'       : SCP-ECG 格式
% - 'ISHNE'         : ISHNE 格式
% - 其他（見 ECG12.m 構造器）

fprintf('正在加載文件: %s\n', ecg_filename);
fprintf('文件格式: %s\n', ecg_format);

try
    % 創建 ECG12 對象 - 這是核心數據結構
    % ECG12 包含所有 12 個導聯的數據以及元數據
    ecg_raw = ECG12(ecg_filename, ecg_format);
    
    fprintf('✓ 加載成功！\n');
    fprintf('  採樣頻率: %d Hz\n', ecg_raw.hz);
    fprintf('  單位: %s\n', ecg_raw.units);
    fprintf('  信號長度: %.2f 秒 (%d 樣本)\n', ...
        length(ecg_raw.I)/ecg_raw.hz, length(ecg_raw.I));
    
catch ME
    % 錯誤處理
    fprintf('✗ 加載失敗！\n');
    fprintf('錯誤信息: %s\n', ME.message);
    fprintf('\n請確認：\n');
    fprintf('  1. 文件路徑是否正確\n');
    fprintf('  2. 文件格式是否匹配\n');
    fprintf('  3. 文件是否已損壞\n');
    return;  % 退出腳本
end

% ECG12 對象結構說明：
% ecg_raw.hz     - 採樣頻率 (Hz)
% ecg_raw.units  - 電壓單位（通常是 'mV'）
% ecg_raw.I      - 導聯 I（肢體導聯）
% ecg_raw.II     - 導聯 II（肢體導聯）
% ecg_raw.III    - 導聯 III（肢體導聯）
% ecg_raw.avR    - 增強導聯 aVR
% ecg_raw.avL    - 增強導聯 aVL
% ecg_raw.avF    - 增強導聯 aVF
% ecg_raw.V1-V6  - 胸前導聯 V1 到 V6

%% ========== 第 1.5 步：可視化原始信號（可選）==========
fprintf('\n正在生成原始 ECG 信號圖...\n');

% 創建時間軸（單位：秒）
time_axis = (0:length(ecg_raw.I)-1) / ecg_raw.hz;

% 創建圖形窗口
figure('Name', '原始 ECG 信號 (12 導聯)', 'NumberTitle', 'off');
set(gcf, 'Position', [100, 100, 1200, 800]);  % 設置窗口大小

% 定義導聯名稱（用於標籤）
lead_names = {'I', 'II', 'III', 'aVR', 'aVL', 'aVF', ...
              'V1', 'V2', 'V3', 'V4', 'V5', 'V6'};

% 獲取所有導聯數據（用於統一 Y 軸範圍）
all_leads = [ecg_raw.I, ecg_raw.II, ecg_raw.III, ...
             ecg_raw.avR, ecg_raw.avL, ecg_raw.avF, ...
             ecg_raw.V1, ecg_raw.V2, ecg_raw.V3, ...
             ecg_raw.V4, ecg_raw.V5, ecg_raw.V6];

% 計算 Y 軸範圍（統一所有子圖）
y_min = min(all_leads(:));
y_max = max(all_leads(:));
y_margin = (y_max - y_min) * 0.1;  % 10% 邊距

% 繪製所有 12 個導聯
for i = 1:12
    subplot(4, 3, i);  % 4 行 3 列佈局
    
    % 根據索引選擇對應導聯
    switch i
        case 1;  lead_data = ecg_raw.I;
        case 2;  lead_data = ecg_raw.II;
        case 3;  lead_data = ecg_raw.III;
        case 4;  lead_data = ecg_raw.avR;
        case 5;  lead_data = ecg_raw.avL;
        case 6;  lead_data = ecg_raw.avF;
        case 7;  lead_data = ecg_raw.V1;
        case 8;  lead_data = ecg_raw.V2;
        case 9;  lead_data = ecg_raw.V3;
        case 10; lead_data = ecg_raw.V4;
        case 11; lead_data = ecg_raw.V5;
        case 12; lead_data = ecg_raw.V6;
    end
    
    % 繪製波形
    plot(time_axis, lead_data, 'b', 'LineWidth', 1);
    
    % 設置圖形屬性
    title(sprintf('導聯 %s', lead_names{i}), 'FontSize', 10, 'FontWeight', 'bold');
    ylabel('電壓 (mV)', 'FontSize', 8);
    ylim([y_min - y_margin, y_max + y_margin]);
    grid on;
    
    % 僅在底部子圖添加 X 軸標籤
    if i > 9
        xlabel('時間 (秒)', 'FontSize', 8);
    end
end

% 添加總標題
sgtitle('原始 ECG 信號（未濾波）', 'FontSize', 14, 'FontWeight', 'bold');

fprintf('✓ 原始信號圖生成完成\n');

%% ========== 第 2 步：設置處理參數 ==========
fprintf('\n==========================================\n');
fprintf('步驟 2: 設置處理參數\n');
fprintf('==========================================\n');

% 創建 Annoparams 對象 - 包含所有處理參數
% Annoparams 是參數容器類，定義了整個處理管道的配置
aps = Annoparams();

% --- 基線校正參數 (Baseline Correction Parameters) ---
% 基線校正用於去除低頻漂移（主要是呼吸運動引起的）
aps.highpass = 1;  % 啟用高通濾波（1=啟用，0=禁用）

% 小波分解層數：層數越高，截止頻率越低
% 典型值範圍：7-11
% - 層數 7: 截止頻率 ≈ 3.9 Hz @ 500 Hz 採樣
% - 層數 8: 截止頻率 ≈ 1.95 Hz @ 500 Hz 採樣
% - 層數 9: 截止頻率 ≈ 0.98 Hz @ 500 Hz 採樣（推薦）
% - 層數 10: 截止頻率 ≈ 0.49 Hz @ 500 Hz 採樣
aps.wavelet_level_highpass = 9;

% 小波基函數選擇：
% - 'db4': Daubechies 4 - 緊支撐，計算快
% - 'db6': Daubechies 6 - 平衡性能（推薦用於 ECG）
% - 'db8': Daubechies 8 - 更平滑
% - 'sym8': Symlet 8 - 近似對稱，相位失真小
% - 'coif4': Coiflet 4 - 對稱性最好，計算量大
aps.wavelet_name_highpass = 'db6';

fprintf('基線校正設置:\n');
fprintf('  啟用狀態: %s\n', mat2str(aps.highpass));
fprintf('  小波基函數: %s\n', aps.wavelet_name_highpass);
fprintf('  分解層數: %d\n', aps.wavelet_level_highpass);
fprintf('  預期截止頻率: ~%.2f Hz\n', ...
    (ecg_raw.hz/2)/(2^aps.wavelet_level_highpass));

% --- 高頻去噪參數 (High-frequency Denoising Parameters) ---
% 高頻去噪用於去除肌電干擾、儀器噪聲等
aps.lowpass = 1;  % 啟用低通濾波（1=啟用，0=禁用）

% 小波分解層數（高頻去噪）
% 典型值範圍：5-8
% 層數越高，平滑程度越大，但可能過度濾波
aps.wavelet_level_lowpass = 6;

% 小波基函數（高頻去噪）
aps.wavelet_name_lowpass = 'db6';

fprintf('\n高頻去噪設置:\n');
fprintf('  啟用狀態: %s\n', mat2str(aps.lowpass));
fprintf('  小波基函數: %s\n', aps.wavelet_name_lowpass);
fprintf('  分解層數: %d\n', aps.wavelet_level_lowpass);

% --- VCG 轉換參數 (VCG Transformation Parameters) ---
% ECG 到 VCG 的轉換矩陣選擇
% 'Kors': Kors 轉換矩陣（推薦，基於迴歸分析）
% 'Dower': Dower 轉換矩陣（經典方法）
aps.transform_matrix_str = 'Kors';

fprintf('\nVCG 轉換設置:\n');
fprintf('  轉換矩陣: %s\n', aps.transform_matrix_str);

% --- R 波檢測參數 (R-peak Detection Parameters) ---
% 最大心率（用於設置檢測閾值和不應期）
% 典型值：180-220 bpm
aps.maxBPM = 200;  % 每分鐘心跳數 (beats per minute)

% 峰值檢測閾值（相對於信號標準差的倍數）
aps.pkthresh = 0.3;  % 較低的值檢測更多峰值，但可能增加誤檢

% 峰值檢測預濾波（使用移動平均平滑）
aps.pkfilter = 5;  % 移動平均窗口大小（樣本數）

fprintf('\nR 波檢測設置:\n');
fprintf('  最大心率: %d bpm\n', aps.maxBPM);
fprintf('  峰值閾值: %.2f\n', aps.pkthresh);
fprintf('  預濾波窗口: %d 樣本\n', aps.pkfilter);

fprintf('\n✓ 參數設置完成\n');

%% ========== 第 3 步：執行濾波處理 ==========
fprintf('\n==========================================\n');
fprintf('步驟 3: 執行濾波處理\n');
fprintf('==========================================\n');

% 估計最大 RR 間期對應的心率（用於自動選擇高通濾波截止頻率）
% 這裡假設最慢心率為 60 bpm（即最大 RR 間期為 1 秒）
maxRR_hr = 60;  % bpm

fprintf('正在執行兩階段濾波...\n');
fprintf('  階段 1: 基線校正（去除低頻漂移）\n');
fprintf('  階段 2: 高頻去噪（去除肌電干擾）\n');

try
    % 調用 ECG12 對象的 filter 方法
    % 這個方法內部會調用 ecgfilter.m 函數
    [ecg_filtered, highpass_level_used] = ecg_raw.filter(maxRR_hr, aps);
    
    fprintf('✓ 濾波處理完成！\n');
    fprintf('  實際使用的高通濾波層數: %s\n', mat2str(highpass_level_used));
    
catch ME
    fprintf('✗ 濾波處理失敗！\n');
    fprintf('錯誤信息: %s\n', ME.message);
    return;
end

% 濾波處理內部執行的操作：
% 1. 對每個導聯應用鏡像擴展（mirror 函數）
%    - 減少小波變換的邊界效應
%    - 信號長度變為原來的 3 倍
%
% 2. 執行小波分解（wavedec 函數）
%    - 將信號分解為近似係數和細節係數
%    - 近似係數代表低頻成分（基線漂移）
%
% 3. 重構並去除基線（wrcoef 函數）
%    - 重構指定層數的近似信號
%    - 從原始信號中減去近似信號
%
% 4. 提取中間部分（middlethird 函數）
%    - 去除鏡像擴展的邊界部分
%    - 恢復原始信號長度
%
% 5. 應用小波去噪（wden 函數）
%    - 使用軟閾值方法
%    - 去除高頻噪聲成分

%% ========== 第 3.5 步：可視化濾波效果（可選）==========
fprintf('\n正在生成濾波對比圖...\n');

% 選擇一個代表性時間段（例如前 5 秒）
display_duration = 5;  % 秒
sample_end = min(display_duration * ecg_raw.hz, length(ecg_raw.I));
sample_indices = 1:sample_end;
time_sample = time_axis(sample_indices);

% 創建對比圖
figure('Name', 'ECG 濾波效果對比', 'NumberTitle', 'off');
set(gcf, 'Position', [100, 100, 1200, 800]);

% 選擇幾個代表性導聯進行對比
compare_leads = [2, 6, 7, 12];  % II, aVF, V1, V6
lead_names_compare = {'II', 'aVF', 'V1', 'V6'};

for i = 1:length(compare_leads)
    subplot(length(compare_leads), 1, i);
    
    % 獲取原始和濾波後的數據
    lead_idx = compare_leads(i);
    switch lead_idx
        case 1;  raw = ecg_raw.I(sample_indices); filtered = ecg_filtered.I(sample_indices);
        case 2;  raw = ecg_raw.II(sample_indices); filtered = ecg_filtered.II(sample_indices);
        case 3;  raw = ecg_raw.III(sample_indices); filtered = ecg_filtered.III(sample_indices);
        case 4;  raw = ecg_raw.avR(sample_indices); filtered = ecg_filtered.avR(sample_indices);
        case 5;  raw = ecg_raw.avL(sample_indices); filtered = ecg_filtered.avL(sample_indices);
        case 6;  raw = ecg_raw.avF(sample_indices); filtered = ecg_filtered.avF(sample_indices);
        case 7;  raw = ecg_raw.V1(sample_indices); filtered = ecg_filtered.V1(sample_indices);
        case 8;  raw = ecg_raw.V2(sample_indices); filtered = ecg_filtered.V2(sample_indices);
        case 9;  raw = ecg_raw.V3(sample_indices); filtered = ecg_filtered.V3(sample_indices);
        case 10; raw = ecg_raw.V4(sample_indices); filtered = ecg_filtered.V4(sample_indices);
        case 11; raw = ecg_raw.V5(sample_indices); filtered = ecg_filtered.V5(sample_indices);
        case 12; raw = ecg_raw.V6(sample_indices); filtered = ecg_filtered.V6(sample_indices);
    end
    
    % 繪製對比
    plot(time_sample, raw, 'Color', [0.7, 0.7, 0.7], 'LineWidth', 1.5);
    hold on;
    plot(time_sample, filtered, 'b', 'LineWidth', 1.5);
    
    % 設置圖形屬性
    title(sprintf('導聯 %s 濾波對比', lead_names_compare{i}), ...
        'FontSize', 11, 'FontWeight', 'bold');
    ylabel('電壓 (mV)', 'FontSize', 9);
    legend('原始信號', '濾波後', 'Location', 'best', 'FontSize', 8);
    grid on;
    
    % 僅在底部子圖添加 X 軸標籤
    if i == length(compare_leads)
        xlabel('時間 (秒)', 'FontSize', 9);
    end
end

% 添加總標題
sgtitle(sprintf('ECG 濾波效果對比（前 %d 秒）', display_duration), ...
    'FontSize', 14, 'FontWeight', 'bold');

fprintf('✓ 濾波對比圖生成完成\n');

%% ========== 第 4 步：轉換為 VCG ==========
fprintf('\n==========================================\n');
fprintf('步驟 4: 轉換為向量心電圖 (VCG)\n');
fprintf('==========================================\n');

fprintf('正在執行 ECG → VCG 轉換...\n');
fprintf('  使用轉換矩陣: %s\n', aps.transform_matrix_str);

try
    % 創建 VCG 對象
    % VCG 包含 X, Y, Z 三個正交分量
    vcg = VCG(ecg_filtered, aps);
    
    fprintf('✓ VCG 轉換完成！\n');
    fprintf('  X 軸: 左 (-) ↔ 右 (+)\n');
    fprintf('  Y 軸: 腳 (-) ↔ 頭 (+)\n');
    fprintf('  Z 軸: 後 (-) ↔ 前 (+)\n');
    fprintf('  VM (Vector Magnitude): sqrt(X² + Y² + Z²)\n');
    
catch ME
    fprintf('✗ VCG 轉換失敗！\n');
    fprintf('錯誤信息: %s\n', ME.message);
    return;
end

% VCG 對象結構說明：
% vcg.hz     - 採樣頻率（與原始 ECG 相同）
% vcg.units  - 電壓單位（與原始 ECG 相同）
% vcg.X      - X 軸分量（左右方向）
% vcg.Y      - Y 軸分量（頭腳方向）
% vcg.Z      - Z 軸分量（前後方向）
% vcg.VM     - 向量幅度（三個分量的向量和）

% 轉換矩陣的作用：
% Kors 矩陣（8x3）將 8 個獨立 ECG 導聯映射到 3 個 VCG 軸
% [X]   [a11 a12 ... a18]   [I  ]
% [Y] = [a21 a22 ... a28] * [II ]
% [Z]   [a31 a32 ... a38]   [V1-V6]

%% ========== 第 4.5 步：可視化 VCG（可選）==========
fprintf('\n正在生成 VCG 信號圖...\n');

figure('Name', 'VCG 信號（三軸分量）', 'NumberTitle', 'off');
set(gcf, 'Position', [100, 100, 1200, 900]);

% 子圖 1: X 軸（左右）
subplot(4, 1, 1);
plot(time_axis, vcg.X, 'r', 'LineWidth', 1.2);
title('VCG X 軸（左 ← → 右）', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('電壓 (mV)', 'FontSize', 9);
grid on;

% 子圖 2: Y 軸（頭腳）
subplot(4, 1, 2);
plot(time_axis, vcg.Y, 'g', 'LineWidth', 1.2);
title('VCG Y 軸（腳 ← → 頭）', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('電壓 (mV)', 'FontSize', 9);
grid on;

% 子圖 3: Z 軸（前後）
subplot(4, 1, 3);
plot(time_axis, vcg.Z, 'b', 'LineWidth', 1.2);
title('VCG Z 軸（後 ← → 前）', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('電壓 (mV)', 'FontSize', 9);
grid on;

% 子圖 4: VM（向量幅度）
subplot(4, 1, 4);
plot(time_axis, vcg.VM, 'k', 'LineWidth', 1.5);
title('VCG 向量幅度 (VM = √(X² + Y² + Z²))', ...
    'FontSize', 11, 'FontWeight', 'bold');
xlabel('時間 (秒)', 'FontSize', 9);
ylabel('電壓 (mV)', 'FontSize', 9);
grid on;

sgtitle('向量心電圖 (VCG) 信號分析', 'FontSize', 14, 'FontWeight', 'bold');

fprintf('✓ VCG 信號圖生成完成\n');

%% ========== 第 5 步：檢測 R 波峰值 ==========
fprintf('\n==========================================\n');
fprintf('步驟 5: 檢測 R 波峰值\n');
fprintf('==========================================\n');

fprintf('正在檢測 R 波位置...\n');
fprintf('  檢測參數:\n');
fprintf('    最大心率: %d bpm\n', aps.maxBPM);
fprintf('    峰值閾值: %.2f\n', aps.pkthresh);

try
    % 調用 VCG 對象的 peaks 方法
    % 返回所有檢測到的 R 波位置（以樣本索引表示）
    QRS_locations = vcg.peaks(aps);
    
    num_beats = length(QRS_locations);
    fprintf('✓ R 波檢測完成！\n');
    fprintf('  檢測到心搏數: %d\n', num_beats);
    
    if num_beats > 1
        % 計算 RR 間期統計
        RR_intervals_samples = diff(QRS_locations);  % 樣本數
        RR_intervals_ms = RR_intervals_samples * 1000 / vcg.hz;  % 毫秒
        
        % 計算心率（每分鐘心跳數）
        heart_rates = 60000 ./ RR_intervals_ms;  % bpm
        
        fprintf('\nRR 間期統計:\n');
        fprintf('  平均 RR 間期: %.1f ms\n', mean(RR_intervals_ms));
        fprintf('  RR 間期範圍: %.1f - %.1f ms\n', ...
            min(RR_intervals_ms), max(RR_intervals_ms));
        fprintf('  RR 間期標準差: %.1f ms\n', std(RR_intervals_ms));
        
        fprintf('\n心率統計:\n');
        fprintf('  平均心率: %.1f bpm\n', mean(heart_rates));
        fprintf('  心率範圍: %.1f - %.1f bpm\n', ...
            min(heart_rates), max(heart_rates));
        fprintf('  心率標準差: %.1f bpm\n', std(heart_rates));
    else
        fprintf('  警告: 檢測到的心搏數量不足，無法計算統計信息\n');
    end
    
catch ME
    fprintf('✗ R 波檢測失敗！\n');
    fprintf('錯誤信息: %s\n', ME.message);
    return;
end

% R 波檢測原理：
% 1. 使用 VM（向量幅度）信號作為檢測基礎
%    - VM 信號對 R 波更敏感，噪聲更小
%
% 2. 應用峰值檢測算法（findpeaksecg.m）
%    - 閾值篩選：信號幅度 > 閾值 * 標準差
%    - 不應期：基於最大心率設置最小 RR 間期
%    - 峰值驗證：確保檢測到的是真正的 R 波
%
% 3. 後處理
%    - 去除偽峰值（T 波等）
%    - 填補漏檢的 R 波

%% ========== 第 5.5 步：可視化 R 波檢測結果（可選）==========
fprintf('\n正在生成 R 波檢測結果圖...\n');

figure('Name', 'R 波檢測結果', 'NumberTitle', 'off');
set(gcf, 'Position', [100, 100, 1400, 600]);

% 子圖 1: 完整信號上的 R 波標記
subplot(2, 1, 1);
plot(time_axis, vcg.VM, 'b', 'LineWidth', 1);
hold on;
% 標記 R 波位置
plot(time_axis(QRS_locations), vcg.VM(QRS_locations), ...
    'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r', 'LineWidth', 1.5);
title('完整信號 - R 波檢測結果', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('時間 (秒)', 'FontSize', 10);
ylabel('電壓 (mV)', 'FontSize', 10);
legend('VCG VM 信號', 'R 波位置', 'Location', 'best');
grid on;

% 子圖 2: 放大顯示前幾個心搏
subplot(2, 1, 2);
if num_beats >= 3
    % 顯示前 3 個心搏
    zoom_start = max(1, QRS_locations(1) - round(0.2*vcg.hz));
    zoom_end = min(length(vcg.VM), QRS_locations(3) + round(0.4*vcg.hz));
    zoom_indices = zoom_start:zoom_end;
    
    plot(time_axis(zoom_indices), vcg.VM(zoom_indices), 'b', 'LineWidth', 1.5);
    hold on;
    
    % 僅標記放大區域內的 R 波
    r_in_zoom = QRS_locations(QRS_locations >= zoom_start & QRS_locations <= zoom_end);
    plot(time_axis(r_in_zoom), vcg.VM(r_in_zoom), ...
        'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r', 'LineWidth', 2);
    
    title('放大視圖 - 前幾個心搏', 'FontSize', 12, 'FontWeight', 'bold');
    xlabel('時間 (秒)', 'FontSize', 10);
    ylabel('電壓 (mV)', 'FontSize', 10);
    legend('VCG VM 信號', 'R 波位置', 'Location', 'best');
    grid on;
else
    text(0.5, 0.5, '心搏數量不足，無法顯示放大視圖', ...
        'HorizontalAlignment', 'center', 'FontSize', 12);
end

sgtitle('R 波峰值檢測與標註', 'FontSize', 14, 'FontWeight', 'bold');

fprintf('✓ R 波檢測結果圖生成完成\n');

%% ========== 第 6 步：生成中位數心搏 ==========
fprintf('\n==========================================\n');
fprintf('步驟 6: 生成中位數心搏\n');
fprintf('==========================================\n');

% 定義中位數心搏所需的最小心搏數
MIN_BEATS_FOR_MEDIAN = 3;  % 至少需要 3 個心搏才能計算有意義的中位數

if num_beats < MIN_BEATS_FOR_MEDIAN
    fprintf('⚠ 警告: 檢測到的心搏數量 (%d) 不足，建議至少 %d 個心搏\n', ...
        num_beats, MIN_BEATS_FOR_MEDIAN);
    fprintf('跳過中位數心搏生成步驟\n');
else
    fprintf('正在生成中位數心搏...\n');
    fprintf('  使用心搏數: %d\n', num_beats);
    
    try
        % 定義心搏窗口參數（可根據需要調整）
        % 這些參數定義了提取心搏的時間窗口
        PRE_R_WINDOW_MS = 200;   % R 波前的時間窗口（毫秒）
        POST_R_WINDOW_MS = 400;  % R 波後的時間窗口（毫秒）
        % 窗口範圍：R 波前 200 ms 到 R 波後 400 ms
        pre_ms = PRE_R_WINDOW_MS;
        post_ms = POST_R_WINDOW_MS;
        
        pre_samples = round(pre_ms * vcg.hz / 1000);   % 轉換為樣本數
        post_samples = round(post_ms * vcg.hz / 1000); % 轉換為樣本數
        
        fprintf('  心搏窗口: R 波前 %d ms 到 R 波後 %d ms\n', pre_ms, post_ms);
        fprintf('  窗口長度: %d 樣本 (%.1f ms)\n', ...
            pre_samples + post_samples, ...
            (pre_samples + post_samples) * 1000 / vcg.hz);
        
        % 計算每個心搏的起始和結束位置
        beat_starts = QRS_locations - pre_samples;
        beat_ends = QRS_locations + post_samples;
        
        % 調用 VCG 對象的 medianbeat 方法
        % 這個方法會：
        % 1. 提取所有心搏片段
        % 2. 對齊到 R 波
        % 3. 計算中位數（逐樣本）
        [medianbeat_vcg, beatsig_vcg] = vcg.medianbeat(beat_starts, beat_ends);
        
        fprintf('✓ 中位數心搏生成完成！\n');
        
        % 中位數心搏的優點：
        % 1. 對異常心搏（如 PVC）不敏感
        % 2. 減少隨機噪聲
        % 3. 提供穩定的形態學特徵
        % 4. 比平均值更魯棒
        
    catch ME
        fprintf('✗ 中位數心搏生成失敗！\n');
        fprintf('錯誤信息: %s\n', ME.message);
        return;
    end
    
    %% ========== 第 6.5 步：可視化中位數心搏（可選）==========
    fprintf('\n正在生成中位數心搏圖...\n');
    
    % 創建中位數心搏的時間軸（以 R 波為中心，單位：毫秒）
    beat_length = length(medianbeat_vcg.VM);
    beat_time_ms = ((0:beat_length-1) - pre_samples) * 1000 / vcg.hz;
    
    figure('Name', '中位數心搏分析', 'NumberTitle', 'off');
    set(gcf, 'Position', [100, 100, 1400, 900]);
    
    % 子圖 1: X 軸分量
    subplot(4, 1, 1);
    plot(beat_time_ms, medianbeat_vcg.X, 'r', 'LineWidth', 1.5);
    hold on;
    plot([0, 0], ylim, 'k--', 'LineWidth', 1);  % R 波位置標記
    title('中位數心搏 - X 軸（左 ← → 右）', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('電壓 (mV)', 'FontSize', 9);
    grid on;
    
    % 子圖 2: Y 軸分量
    subplot(4, 1, 2);
    plot(beat_time_ms, medianbeat_vcg.Y, 'g', 'LineWidth', 1.5);
    hold on;
    plot([0, 0], ylim, 'k--', 'LineWidth', 1);
    title('中位數心搏 - Y 軸（腳 ← → 頭）', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('電壓 (mV)', 'FontSize', 9);
    grid on;
    
    % 子圖 3: Z 軸分量
    subplot(4, 1, 3);
    plot(beat_time_ms, medianbeat_vcg.Z, 'b', 'LineWidth', 1.5);
    hold on;
    plot([0, 0], ylim, 'k--', 'LineWidth', 1);
    title('中位數心搏 - Z 軸（後 ← → 前）', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('電壓 (mV)', 'FontSize', 9);
    grid on;
    
    % 子圖 4: VM（向量幅度）
    subplot(4, 1, 4);
    plot(beat_time_ms, medianbeat_vcg.VM, 'k', 'LineWidth', 2);
    hold on;
    plot([0, 0], ylim, 'k--', 'LineWidth', 1);
    title('中位數心搏 - VM (向量幅度)', 'FontSize', 11, 'FontWeight', 'bold');
    xlabel('時間（相對於 R 波，毫秒）', 'FontSize', 9);
    ylabel('電壓 (mV)', 'FontSize', 9);
    grid on;
    
    % 在所有子圖上添加垂直線標記 R 波位置
    for i = 1:4
        subplot(4, 1, i);
        text(0, max(ylim)*0.9, '← R 波', 'FontSize', 9, ...
            'HorizontalAlignment', 'left', 'Color', 'red', 'FontWeight', 'bold');
    end
    
    sgtitle(sprintf('中位數心搏（基於 %d 個心搏）', num_beats), ...
        'FontSize', 14, 'FontWeight', 'bold');
    
    fprintf('✓ 中位數心搏圖生成完成\n');
end

%% ========== 第 7 步：處理流程總結 ==========
fprintf('\n==========================================\n');
fprintf('處理流程總結\n');
fprintf('==========================================\n');

fprintf('\n【輸入】\n');
fprintf('  文件名: %s\n', ecg_filename);
fprintf('  格式: %s\n', ecg_format);
fprintf('  採樣頻率: %d Hz\n', ecg_raw.hz);
fprintf('  信號長度: %.2f 秒 (%d 樣本)\n', ...
    length(ecg_raw.I)/ecg_raw.hz, length(ecg_raw.I));

fprintf('\n【處理步驟】\n');
fprintf('  ✓ 步驟 1: ECG 數據加載\n');
fprintf('  ✓ 步驟 2: 處理參數設置\n');
fprintf('  ✓ 步驟 3: 兩階段濾波\n');
fprintf('      - 基線校正（小波: %s, 層數: %d）\n', ...
    aps.wavelet_name_highpass, aps.wavelet_level_highpass);
fprintf('      - 高頻去噪（小波: %s, 層數: %d）\n', ...
    aps.wavelet_name_lowpass, aps.wavelet_level_lowpass);
fprintf('  ✓ 步驟 4: ECG → VCG 轉換（%s 矩陣）\n', aps.transform_matrix_str);
fprintf('  ✓ 步驟 5: R 波檢測\n');
if num_beats >= 3
    fprintf('  ✓ 步驟 6: 中位數心搏生成\n');
end

fprintf('\n【輸出】\n');
fprintf('  濾波後的 ECG: ecg_filtered 對象\n');
fprintf('  VCG 數據: vcg 對象\n');
fprintf('  R 波位置: QRS_locations 數組 (%d 個峰值)\n', num_beats);
if num_beats >= 3
    fprintf('  中位數心搏: medianbeat_vcg 對象\n');
    fprintf('  所有心搏集合: beatsig_vcg 對象\n');
end

if num_beats > 1
    fprintf('\n【心率統計】\n');
    fprintf('  平均心率: %.1f bpm\n', mean(heart_rates));
    fprintf('  心率範圍: %.1f - %.1f bpm\n', ...
        min(heart_rates), max(heart_rates));
end

fprintf('\n==========================================\n');
fprintf('處理完成！\n');
fprintf('==========================================\n');

%% ========== 附加說明 ==========
fprintf('\n【後續分析建議】\n');
fprintf('  1. 基準點標註（Fiducial Point Annotation）\n');
fprintf('     - 標註 P, Q, R, S, T 波的起始、峰值和結束點\n');
fprintf('     - 使用 BRAVEHEART 的神經網絡自動標註功能\n');
fprintf('\n');
fprintf('  2. 臨床參數計算\n');
fprintf('     - QT 間期、QRS 寬度、PR 間期\n');
fprintf('     - QT 校正（QTc）：Bazett, Fridericia 等公式\n');
fprintf('     - 心率變異性（HRV）分析\n');
fprintf('\n');
fprintf('  3. 形態學分析\n');
fprintf('     - QRS 軸、T 軸\n');
fprintf('     - 空間 QRS-T 角\n');
fprintf('     - 向量環路面積\n');
fprintf('\n');
fprintf('  4. 高級分析\n');
fprintf('     - 全局電異質性（GEH）\n');
fprintf('     - 空間心室梯度（SVG）\n');
fprintf('     - 心室復極異常檢測\n');

fprintf('\n【參考文檔】\n');
fprintf('  - 用戶手冊: braveheart_userguide.pdf\n');
fprintf('  - 方法說明: braveheart_methods.pdf\n');
fprintf('  - 變量定義: braveheart_variables.pdf\n');
fprintf('  - 中文處理流程: ECG_處理流程說明.md\n');

fprintf('\n【技術支持】\n');
fprintf('  - GitHub: https://github.com/BIVectors/BRAVEHEART\n');
fprintf('  - Email: braveheart.ecg@gmail.com\n');

fprintf('\n腳本執行結束。\n\n');
