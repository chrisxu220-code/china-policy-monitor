# =======================================================
# 1. SETUP & LIBRARIES
# =======================================================
required_packages <- c("tidyverse", "jiebaR", "stm", "quanteda", "readxl", "writexl", "stringi")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages)) install.packages(new_packages)

library(tidyverse)
library(jiebaR)
library(stm)
library(quanteda)
library(readxl)
library(writexl)
library(stringi)

# Set Locale for Chinese Characters
Sys.setlocale("LC_ALL", "zh_CN.UTF-8")

# =======================================================
# 2. AUTO-DOWNLOAD MODEL LOGIC
# =======================================================
# Define paths using relative directories
model_dir <- "models"
data_dir <- "data"
model_path <- file.path(model_dir, "tm_2.stm_auto.RData")

# Create directories if they don't exist
if (!dir.exists(model_dir)) dir.create(model_dir)
if (!dir.exists(data_dir)) dir.create(data_dir)

# Check and Download Model
if (!file.exists(model_path)) {
  message("Model file not found. Downloading from GitHub Releases (this may take a minute)...")
  # Your specific Release URL
  model_url <- "https://github.com/chrisxu220-code/china-policy-monitor/releases/download/v1.0/tm_2.stm_auto.medium.version4.-2.RData"
  # Note: mode = "wb" is crucial for binary files on Windows/Mac
  download.file(model_url, destfile = model_path, mode = "wb")
}

# Load the model
load(model_path)
# Ensure the loaded object is assigned to 'stm_model'
if (exists("out")) {
  stm_model <- out
  rm(out) # Clean up memory
}

# =======================================================
# 3. DATA LOADING (Replaces Absolute Paths)
# =======================================================
# Load helper files from the 'data/' folder
# Note: Ensure these files exist in your data folder!

keywords <- read_csv(file.path(data_dir, "keywords.csv"), show_col_types = FALSE)
city_list <- readLines(file.path(data_dir, "city_list.txt"), warn = FALSE)
single_removed <- readLines(file.path(data_dir, "stm_single_vocab_removed.txt"), warn = FALSE)
custom_topic_df <- read_csv(file.path(data_dir, "Topic Labels - 74.csv"), show_col_types = FALSE)

# Load your Analysis Data
# For the repo, usually, you upload a sample file. 
# Here I assume you have a file named 'policy_data.xlsx' in data folder.
# Change this filename to whatever you actually uploaded.
target_file <- file.path(data_dir, "policy_sample.xlsx") 

if(file.exists(target_file)) {
  data <- read_excel(target_file)
} else {
  stop("Please place your data file (e.g., policy_sample.xlsx) in the 'data/' folder.")
}

# =======================================================
# 4. TEXT PRE-PROCESSING & SEGMENTATION
# =======================================================

# Initialize Jieba Worker using local dictionary files
jiebaa <- worker(type = "mix", 
                 user = file.path(data_dir, "add_word.txt"), 
                 stop_word = file.path(data_dir, "cn_stopwords.txt"))

# A. Basic Jieba Segmentation
message("Segmenting text...")
data$segmentedtext_jieba <- sapply(data$Content, function(x) {
  if(is.na(x)) return("")
  segment(x, jiebaa) %>% paste(collapse = " ")
})

# B. Cleaning Function (Modularized)
clean_text_logic <- function(text_col) {
  # Remove specific phrases
  text_col <- gsub("中国\\s制造\\s2025", "中国制造2025", text_col)
  
  # Remove Year Words (Eleven-Five to Fourteen-Five, and specific years)
  years <- c("十一五", "十二五", "十三五", "十四五", "2000", "2005", "2010", "2015", "2020", "2030", "2035", "2040", "2045", "2050", "2060")
  year_pattern <- paste0(years, collapse = "|")
  text_col <- gsub(year_pattern, "", text_col)
  
  # Remove "2025" unless it's part of "Made in China 2025"
  text_col <- str_replace_all(text_col, "(?<![\\p{Han}])2025", "")
  
  # Remove Locations (Provinces and Cities)
  # Constructing a massive regex for cities can be slow, so we iterate
  # Optimized: Use stringi for faster replacement if list is long
  province_list <- c('上海','云南','内蒙古','北京','吉林','四川','天津','宁夏','安徽','山东','山西','广东','广西','新疆','江苏','江西','河北','河南','浙江','海南','湖北','湖南','甘肃','福建','西藏','贵州','辽宁','重庆','陕西','青海','黑龙江', '自治区', '壮族')
  
  all_locations <- c(province_list, city_list)
  # Remove locations (Naive loop - good enough for moderate data)
  for(loc in all_locations) {
    text_col <- gsub(loc, "", text_col, fixed = TRUE)
  }
  
  # Remove standalone numbers and specific characters
  text_col <- gsub("\\b(?:[一二三四五六七八九]|十[一二三四五六七八九]?)\\b", "", text_col)
  text_col <- gsub("\\b(?:家|市|区县|达|项|号|省)\\b", "", text_col)
  
  # Remove English spacing issues
  text_col <- gsub("\\s[A-Za-z]\\s", " ", text_col)
  
  return(text_col)
}

message("Cleaning text...")
data$segmentedtext_jieba <- clean_text_logic(data$segmentedtext_jieba)

# =======================================================
# 5. FIT NEW DOCUMENTS TO STM MODEL
# =======================================================

message("Processing for STM...")
processed <- textProcessor(documents = data$segmentedtext_jieba,
                           metadata = data,
                           language = "zh",
                           removenumbers = TRUE,
                           removepunctuation = TRUE,
                           stem = FALSE)

# Align Vocabulary
# Function to filter documents based on original model's vocab
align_vocab <- function(doc, vocab, model_vocab) {
  valid_indices <- match(vocab[doc[1, ]], model_vocab)
  valid_indices <- na.omit(valid_indices)
  valid_counts <- doc[2, ][!is.na(match(vocab[doc[1, ]], model_vocab))]
  if(length(valid_indices) == 0) return(NULL)
  matrix(c(valid_indices, valid_counts), nrow = 2, byrow = TRUE)
}

# Apply alignment
docs_aligned <- lapply(processed$documents, align_vocab, 
                       vocab = processed$vocab, 
                       model_vocab = stm_model$vocab)

# Fit New Documents
message("Scoring new documents against the model...")
fitting <- fitNewDocuments(model = stm_model, 
                           documents = docs_aligned, 
                           newData = processed$meta)

theta_df <- as.data.frame(fitting$theta)

# =======================================================
# 6. OUTPUT RESULTS
# =======================================================

# A. Rename Columns with Human Readable Labels
custom_topic_df <- custom_topic_df %>% mutate(full_label = paste0(custom_topic, ": ", names))
colnames(theta_df) <- custom_topic_df$full_label

# B. Save Top 10 Topics
top_10_names <- names(sort(colSums(theta_df), decreasing = TRUE)[1:10])
top_10_df <- theta_df %>% select(all_of(top_10_names))
write_xlsx(top_10_df, "top_10_topics.xlsx")

# C. Grouped Analysis
topic_groups <- list(
  "R&D Strategies" = c(1, 2, 14, 15, 24, 28, 33, 43, 57, 64, 65, 67),
  "Tech Commercialization" = c(4, 20, 39, 40, 51, 53, 71),
  "S&T Policy & Finance" = c(5, 6, 19, 22, 25, 29, 37, 52, 59, 68),
  "Green Tech" = c(8, 13, 31, 41, 45, 54, 69),
  "Biomedical" = c(9, 32, 38, 72),
  "ICT" = c(21, 34, 47, 48, 73),
  "Material Science" = c(50, 56),
  "Agri-Tech" = c(23, 60, 63, 70),
  "Regional Econ Dev" = c(3, 10, 27, 30, 36, 44),
  "Mass Promotion" = c(16, 17, 26),
  "Infrastructure" = c(7, 12, 55, 61, 62, 58),
  "Miscellaneous" = c(11, 42, 49, 66)
)

# Calculate Group Scores
grouped_df <- data.frame(matrix(ncol = length(topic_groups), nrow = nrow(theta_df)))
colnames(grouped_df) <- names(topic_groups)

for (group in names(topic_groups)) {
  indices <- topic_groups[[group]]
  # Map topic index to column name in theta_df (Column 1 is Topic 1, etc.)
  # Note: theta_df columns are now named strings, so we need to be careful.
  # Safer to use raw fitting$theta for index access
  grouped_df[[group]] <- rowSums(fitting$theta[, indices], na.rm = TRUE)
}

# Bind Metadata + Group Scores
final_result <- cbind(data, grouped_df)
write_xlsx(final_result, "policy_scored_results.xlsx")

message("Analysis Complete! Check 'policy_scored_results.xlsx'.")