# ECG 數據處理中文文檔 / ECG Data Processing Chinese Documentation

## 概述 / Overview

本目錄包含 BRAVEHEART ECG 數據處理的完整中文文檔和示例代碼。

This directory contains comprehensive Chinese documentation and example code for BRAVEHEART ECG data processing.

---

## 文檔列表 / Documentation Files

### 1. ECG_處理流程說明.md
**完整的 ECG 處理流程技術文檔**

包含內容：
- ECG 數據加載原理和方法
- 基線校正（Baseline Correction）詳細說明
  - 小波變換理論
  - wander_remove 函數實現
  - 參數選擇指南
- 濾波處理（Filtering）技術細節
  - 高頻去噪方法
  - ecgfilter 函數詳解
- 完整處理管道說明
- 多個代碼示例和參數調優指南

適合對象：
- 需要深入理解 ECG 信號處理原理的研究人員
- 希望自定義處理參數的高級用戶
- 程序員和算法工程師

### 2. example_ecg_processing_workflow_zh.m
**帶詳細中文註解的完整工作流程示例**

包含內容：
- 從數據加載到分析的完整流程
- 每個步驟的詳細中文註解
- 可視化示例
- 錯誤處理和調試技巧
- 處理參數的詳細說明

適合對象：
- MATLAB 用戶
- 需要快速上手的研究人員
- 希望學習完整處理流程的新用戶

---

## 快速開始 / Quick Start

### 方法 1：閱讀文檔
```bash
# 打開 Markdown 文檔
open ECG_處理流程說明.md
```

### 方法 2：運行示例代碼
```matlab
% 在 MATLAB 中運行
cd /path/to/BRAVEHEART
example_ecg_processing_workflow_zh
```

**注意**：運行示例代碼前，請先準備一個 ECG 文件，並修改腳本中的文件路徑：
```matlab
ecg_filename = 'your_ecg_file.xml';  % 修改為您的文件路徑
ecg_format = 'muse_xml';              % 修改為對應的格式
```

---

## 主要處理步驟 / Main Processing Steps

```
1. 加載 ECG 數據 (Load ECG Data)
   └─ ECG12 類構造器
   
2. 基線校正 (Baseline Correction)
   ├─ 鏡像擴展 (mirror)
   ├─ 小波分解 (wavedec)
   ├─ 重構和減法 (wrcoef)
   └─ 提取中間部分 (middlethird)
   
3. 高頻去噪 (High-frequency Denoising)
   └─ 小波閾值去噪 (wden)
   
4. VCG 轉換 (VCG Transformation)
   └─ Kors/Dower 轉換矩陣
   
5. R 波檢測 (R-peak Detection)
   └─ 峰值檢測算法
   
6. 中位數心搏生成 (Median Beat Generation)
   └─ 心搏對齊和中位數計算
```

---

## 關鍵概念說明 / Key Concepts

### 基線校正 (Baseline Correction)
使用小波變換高通濾波去除低頻基線漂移，主要針對呼吸運動引起的信號偏移。

**核心函數**：`wander_remove.m`
**關鍵參數**：
- `wavelet_level_highpass`: 小波分解層數（推薦 9）
- `wavelet_name_highpass`: 小波基函數（推薦 'db6'）

### 高頻去噪 (High-frequency Denoising)
使用小波閾值去噪去除肌電干擾和儀器噪聲。

**核心函數**：`wden` (MATLAB 內建)
**關鍵參數**：
- `wavelet_level_lowpass`: 小波分解層數（推薦 6）
- `wavelet_name_lowpass`: 小波基函數（推薦 'db6'）

### VCG 轉換 (VCG Transformation)
將 12 導聯 ECG 轉換為 3 個正交向量（X, Y, Z）。

**轉換矩陣**：
- **Kors**: 基於迴歸分析，推薦使用
- **Dower**: 經典方法，基於心臟偶極子模型

---

## 推薦參數組合 / Recommended Parameter Sets

### 標準處理（適合大多數情況）
```matlab
aps = Annoparams();
aps.highpass = 1;
aps.wavelet_level_highpass = 9;
aps.wavelet_name_highpass = 'db6';
aps.lowpass = 1;
aps.wavelet_level_lowpass = 6;
aps.wavelet_name_lowpass = 'db6';
aps.transform_matrix_str = 'Kors';
```

### 強基線校正（嚴重基線漂移）
```matlab
aps.wavelet_level_highpass = 10;  % 更高層數
aps.wavelet_name_highpass = 'sym8';  % 更對稱的小波
```

### 輕度處理（保留更多特徵）
```matlab
aps.wavelet_level_highpass = 8;  % 較低層數
aps.wavelet_level_lowpass = 5;   % 較輕的去噪
```

---

## 常見問題 / FAQ

### Q1: 濾波後 QRS 波形失真？
**A**: 降低高頻去噪層數（從 7 降到 5-6），或更換小波基（使用 db4 而非 db8）。

### Q2: 基線仍然不穩定？
**A**: 增加基線校正層數（從 9 增到 10-11），或使用更對稱的小波（sym8）。

### Q3: 如何選擇小波分解層數？
**A**: 根據採樣頻率和目標截止頻率：
- 截止頻率 ≈ (採樣頻率 / 2) / 2^層數
- 例如：500 Hz 採樣，層數 9 → 截止頻率 ≈ 0.98 Hz

### Q4: 支持哪些 ECG 格式？
**A**: 支持 20+ 種格式，包括：
- GE MUSE XML
- Philips XML
- DICOM
- HL7 XML
- SCP-ECG
- 更多格式見主 README.md

---

## 相關資源 / Related Resources

### BRAVEHEART 官方文檔
- 用戶手冊：`braveheart_userguide.pdf`
- 方法說明：`braveheart_methods.pdf`
- 變量定義：`braveheart_variables.pdf`

### 在線資源
- GitHub: https://github.com/BIVectors/BRAVEHEART
- 論文: [Computer Methods and Programs in Biomedicine, 2023](https://doi.org/10.1016/j.cmpb.2023.107798)

### 技術支持
- Email: braveheart.ecg@gmail.com

---

## 文件結構 / File Structure

```
BRAVEHEART/
├── ECG_處理流程說明.md              # 技術文檔（本文件）
├── example_ecg_processing_workflow_zh.m  # 示例代碼
├── README_zh.md                      # 本說明文件
├── load_ecg.m                        # ECG 加載函數
├── ecgfilter.m                       # 濾波函數
├── wander_remove.m                   # 基線校正函數
├── ECG12.m                           # ECG 類定義
├── VCG.m                             # VCG 類定義
├── Annoparams.m                      # 參數類定義
└── ...（其他源文件）
```

---

## 貢獻 / Contributing

如果您發現文檔中的錯誤或有改進建議，請通過以下方式聯繫：
- GitHub Issues: https://github.com/BIVectors/BRAVEHEART/issues
- Email: braveheart.ecg@gmail.com

---

## 許可證 / License

本文檔和示例代碼遵循 BRAVEHEART 的 GPL-3.0 許可證。
詳見主目錄的 LICENSE 文件。

---

## 更新日誌 / Changelog

### 2025-01-09
- 初始版本發布
- 添加完整的中文技術文檔
- 添加帶詳細註解的示例代碼
- 包含參數調優指南和常見問題解答

---

**版權所有 © 2016-2025 Jonathan W. Waks and Hans F. Stabenau**
