# 🇨🇳 China Tech Policy Monitor | Structural Topic Modeling (STM) Dashboard

An interactive NLP dashboard designed to quantify and visualize shifts in Chinese industrial policy. This tool leverages a pre-trained **Structural Topic Model (STM)** to map unseen government documents against 74 distinct policy topics (e.g., "Made in China 2025", "Green Energy", "R&D Financing").

Built with **R Shiny**, this project features an automated model provisioning architecture that decouples the heavy model weights from the codebase, ensuring a lightweight and reproducible repository.

## 🚀 Key Features

* **Automated Model Provisioning:** The application automatically detects if the pre-trained model weights (200MB+) are missing and securely downloads them from GitHub Releases upon the first launch.
* **Real-time NLP Scoring:** Upload any new policy document (Excel/CSV), and the system uses `fitNewDocuments` to project it onto the existing 74-dimensional topic space.
* **Advanced Chinese Pre-processing:** Integrated `jiebaR` segmentation pipeline with custom stop-word removal, regex cleaning for administrative terms (e.g., "省", "市"), and temporal filtering.
* **Thematic Aggregation:** Automatically aggregates micro-topics into 12 macro-strategic groups (e.g., "Research & Development", "Tech Commercialization").

## 🛠 Tech Stack

* **Core Logic:** R Language
* **Web Framework:** R Shiny
* **NLP & Modeling:** `stm` (Structural Topic Model), `jiebaR` (Chinese Segmentation), `quanteda`
* **Data Manipulation:** `tidyverse`, `stringi`

## 📂 Repository Structure

```text
china-policy-monitor/
│
├── app.R                  # Main application entry point (UI & Server)
├── data/                  # NLP Assets & Dictionaries
│   ├── add_word.txt       # Custom user dictionary for Jieba
│   ├── cn_stopwords.txt   # Stopwords list
│   └── Topic Labels.csv   # Mapping of Topic IDs to human-readable names
├── models/                # (Auto-created) Stores the downloaded .RData model
└── README.md              # Project documentation
