# =======================================================
# app.R - Main Dashboard File
# =======================================================

library(shiny)
library(tidyverse)
library(jiebaR)
library(stm)
library(readxl)
library(writexl)
library(quanteda)
library(stringi)

# -------------------------------------------------------
# 1. GLOBAL SETUP (Runs once when app starts)
# -------------------------------------------------------

# --- A. Auto-Download Model Logic ---
model_path <- "models/tm_2.stm_auto.RData"

# Create the models folder if it doesn't exist
if (!dir.exists("models")) {
  dir.create("models")
}

# If the model file is missing, download it from GitHub Releases
if (!file.exists(model_path)) {
  message("Model file not found. Downloading from GitHub Releases...")
  
  # This is the link to your specific release asset
  model_url <- "https://github.com/chrisxu220-code/china-policy-monitor/releases/download/v1.0/tm_2.stm_auto.medium.version4.-2.RData"
  
  # mode = "wb" is crucial for binary files
  download.file(model_url, destfile = model_path, mode = "wb")
}

# Load the model (This creates 'out' or 'stm_model' in memory)
load(model_path)

# Ensure the model object is consistently named 'stm_model'
# (Your original RData file likely loads an object named 'out')
if(exists("out")) {
  stm_model <- out
  rm(out) # Clean up memory
}

# --- B. Prepare Jieba Dictionary ---
# We use the pre-uploaded dictionary file directly from the 'data' folder
# This is faster and more reliable than regenerating it from CSV

jiebaa <- worker(type = "mix", 
                 user = "data/add_word.txt", 
                 stop_word = "data/cn_stopwords.txt")

# --- C. Load Helper Lists ---
# Load single character stop words to remove
single_removed <- readLines("data/stm_single_vocab_removed.txt", warn = FALSE)

# Load Topic Labels for visualization
custom_topic_df <- read_csv("data/Topic Labels - 74.csv", show_col_types = FALSE)
# Create a combined label string (Topic Number + Name)
custom_topic_df <- custom_topic_df |> 
  mutate(topic = paste0(custom_topic, ": ", names))

# -------------------------------------------------------
# 2. USER INTERFACE (UI)
# -------------------------------------------------------
ui <- fluidPage(
  titlePanel("🇨🇳 China Tech Policy Analyzer (STM)"),
  
  sidebarLayout(
    sidebarPanel(
      # Input: File Upload
      fileInput("file1", "Upload Policy Excel/CSV",
                multiple = FALSE,
                accept = c(".xlsx", ".csv")),
      helpText("Note: The uploaded file MUST have a column named 'Content' containing the Chinese text."),
      
      hr(),
      
      h4("Model Info"),
      helpText("Model: STM (K=74)"),
      helpText("Trained by: Xiaohan Wu (UCSD)"),
      
      hr(),
      
      # Output: Download Button
      downloadButton("downloadData", "Download Scored Results")
    ),
    
    mainPanel(
      tabsetPanel(
        tabPanel("Data Preview", tableOutput("head_table")),
        tabPanel("Topic Distribution", plotOutput("topic_plot")),
        tabPanel("Grouped Analysis", tableOutput("group_table"))
      )
    )
  )
)

# -------------------------------------------------------
# 3. SERVER LOGIC
# -------------------------------------------------------
server <- function(input, output) {
  
  # --- Reactive: Read Uploaded File ---
  raw_data <- reactive({
    req(input$file1)
    
    # Check file extension to use correct reader
    ext <- tools::file_ext(input$file1$name)
    if(ext == "xlsx"){
      df <- read_excel(input$file1$datapath)
    } else {
      df <- read_csv(input$file1$datapath, show_col_types = FALSE)
    }
    return(df)
  })
  
  # --- Reactive: Clean & Process Text ---
  processed_data <- reactive({
    data <- raw_data()
    
    # Validation: Ensure 'Content' column exists
    if(!"Content" %in% names(data)) {
      showNotification("Error: Uploaded file must have a 'Content' column!", type = "error")
      return(NULL)
    }
    
    # 1. Jieba Segmentation
    # Apply segmentation to every row in 'Content'
    data$segmentedtext_jieba <- sapply(data$Content, function(x) {
      if(is.na(x)) return("")
      segment(x, jiebaa) |> paste(collapse = " ")
    })
    
    # 2. Cleaning Logic (Regex)
    # Remove Chinese numbers (一二三...)
    data$segmentedtext_jieba <- gsub("\\b(?:[一二三四五六七八九]|十[一二三四五六七八九]?)\\b", "", data$segmentedtext_jieba)
    # Remove standalone administrative words (省, 市, 区...)
    data$segmentedtext_jieba <- gsub("\\b(?:家|市|区县|达|项|号|省)\\b", "", data$segmentedtext_jieba)
    # Remove English characters with spaces
    data$segmentedtext_jieba <- gsub("\\s[A-Za-z]\\s", " ", data$segmentedtext_jieba)
    
    # 3. STM Text Processor
    # Converts text into the format STM expects
    processed <- textProcessor(documents = data$segmentedtext_jieba,
                               metadata = data,
                               language = "zh",
                               removenumbers = TRUE,
                               removepunctuation = TRUE,
                               stem = FALSE)
    return(processed)
  })
  
  # --- Reactive: Fit New Documents ---
  model_results <- reactive({
    new_docs <- processed_data()
    req(new_docs)
    
    # Align Vocabulary
    # fitNewDocuments aligns the new text with the original model's vocabulary
    fitting <- fitNewDocuments(model = stm_model, 
                               documents = new_docs$documents, 
                               newData = new_docs$meta)
    
    return(fitting$theta) # Theta = Topic Proportions per Document
  })
  
  # --- Output: Data Preview ---
  output$head_table <- renderTable({
    req(raw_data())
    head(raw_data(), 5)
  })
  
  # --- Output: Topic Plot ---
  output$topic_plot <- renderPlot({
    req(model_results())
    theta <- model_results()
    
    # Assign human-readable names to columns
    colnames(theta) <- custom_topic_df$topic
    
    # Calculate average prevalence of topics in this batch
    top_topics <- sort(colSums(theta), decreasing = TRUE)[1:10]
    
    # Plot
    par(mar=c(5, 15, 4, 2)) # Adjust margins for long labels
    barplot(top_topics, 
            main = "Top 10 Topics in Uploaded Documents", 
            horiz = TRUE, 
            las = 1, # Horizontal axis labels
            cex.names = 0.8)
  })
  
  # --- Output: Grouped Analysis Table ---
  output$group_table <- renderTable({
    req(model_results())
    theta <- model_results()
    
    # Define Topic Groups (Hardcoded mapping from your research)
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
    
    # Aggregate scores by group
    group_scores <- sapply(names(topic_groups), function(group_name) {
      indices <- topic_groups[[group_name]]
      sum(theta[, indices]) # Total weight of this group in the batch
    })
    
    # Create a nice table
    data.frame(
      Group = names(group_scores),
      Total_Weight = group_scores
    ) %>% arrange(desc(Total_Weight))
  })
  
  # --- Output: Download Handler ---
  output$downloadData <- downloadHandler(
    filename = function() { 
      paste0("policy_scored_", Sys.Date(), ".xlsx") 
    },
    content = function(file) {
      theta <- model_results()
      # Assign readable names
      colnames(theta) <- custom_topic_df$topic
      
      # Bind original data with topic scores
      final_df <- cbind(raw_data(), theta)
      write_xlsx(final_df, file)
    }
  )
}

# Run the Application
shinyApp(ui = ui, server = server)
