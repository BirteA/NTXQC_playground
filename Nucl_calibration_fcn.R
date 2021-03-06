##### Functions for Calibration samples - Nucleotides -------------------

#' @title Import files
#'
#' @description \code{import_files} imports all files exported vie TOPPAS pipeline stored
#' at a defined input folder.
#' It also takes care of required modificiations of the input data, e.g., extraction
#' of file names and renaming column names.
#'
#' @param path_files Character.
#' @param mode Character; define either as "samples" or "cal" for calibration files
#' @param conv_list Data frame; containing conversion information, e.g., nuc_nb into nuc_id
#' @param condition_list Data frame: containing concentration level for each calibration curve, 
#' required for the mode + "calibrations". Default value - NULL.
#' @param plot_graph TRUE / FALSE for the graphical output
#'
#' @return The function returns a dataframe summarising all input information provided in the
#' single input files
#'
#' @examples import_files("input/samples/", mode = "samples")
#' @examples import_files("input/cal/", mode = "cal")
#'
#' @export
import_files <- function(path_files, mode, conv_list, condition_list, plot_graph = FALSE){
  
  dataframe = list.files(path_files, pattern = ".unknown")
  
  l = list()
  temp = list()
  
  for (i in 1:length(dataframe)) {
    
    #import *.unknown file
    data = read.table(paste0(path_files, dataframe[i]), header = TRUE)
    
    #clean up header
    colnames(data)[grepl("median", colnames(data))] = "median_intensity"
    colnames(data)[grepl("nuc", colnames(data))] = "nuc_nb"
    
    #### transformation for data == calibration --------------------------------
    if (mode == "cal") {
      #extract: what NucleoMix
      data$calcurve = unlist(strsplit(dataframe[i], split = "_", fixed = TRUE))[4]
      
      #extract: replicate calcurve
      temp = unlist(strsplit(dataframe[i], split = "_", fixed = TRUE))[5]
      data$repl_calcurve = as.numeric(unlist(strsplit(temp, split = ".", fixed = TRUE))[1])
      
      #extract: date
      data$date = unlist(strsplit(dataframe[i], split = "_", fixed = TRUE))[1]
      
      #merge: nuc_nb matching up with nuc_id
      data_conv = merge(data, conv_list)
      
      #merge: calibration curve concentrations
      data_conv = merge(data_conv, condition_list, all.x = TRUE)
      
      #transform: transition (numeric) into factor()
      data_conv = ddply(data_conv, c("nuc_id", "transition"), transform, 
                        transition_id = paste0("t", transition))
      
      #select dataframe columns
      data_conv = data_conv[, c("nuc_id", "nuc","nuc_group" ,"transition_id", "calcurve", "level" ,"repl_calcurve", 
                                "date", "median_intensity", "cv")]
    }
    
    #### transformation for data == samples ------------------------------------
    if (mode == "samples") {
      
      #extract: 
      data$file_tag = unlist(strsplit(dataframe[i], split = "_", fixed = TRUE))[3]
      data$date = unlist(strsplit(dataframe[i], split = "_", fixed = TRUE))[1]
      
      #merge: sample group annotaion
      data_conv = merge(data, conv_list, all.x = TRUE)
      
      #merge: add annotation
      data_conv = merge(data_conv, condition_list, all.x = TRUE)
      
      #transform: transition (numeric) into factor()
      data_conv = ddply(data_conv, c("nuc_id", "transition"), transform, 
                        transition_id = paste0("t", transition))
      
      #select dataframe columns
      data_conv = data_conv[, c("date","file_tag", "sample", "nuc_id", "nuc", "transition_id",  
                                "median_intensity", "cv")]
    }
    
    
    #write list and transform into a dataframe
    l[[i]] = data_conv
  }
  
  data_export = do.call(rbind, l)
  
  #check matching annotation file (empty file)
  if (nrow(data_export) == 0) {
    message("ERROR: Check annotation file. Empty dataframe created!")
  } else {
    message("Checked - successful merge annotation file and input data!")
  }
  
  #export into .csv file
  temp_extr = unlist(strsplit(path_files, split = "/", fixed = TRUE))[2]
  write.csv(data_export, paste0("output/", temp_extr, "_export.csv"), row.names = FALSE)
  message("Done - input data exported as .csv-file: ",temp_extr)
  
  
  if (plot_graph == TRUE) {
    
    for (var in unique(data_export$nuc_group)) {
      print(
        ggplot(subset(data_export, data_export$nuc_group == var & data_export$calcurve != "TrueBlank"), 
               aes(x = level, y = median_intensity, colour = date)) + 
          geom_point() + 
          facet_grid(nuc~transition_id, scales = "free_y") + 
          theme_bw() + 
          theme(axis.text.x = element_text(size = 6),
                axis.text.y = element_text(size = 8)) +
          ggtitle(paste0("Nucleotide (Calibration): ", var)) +
          theme(strip.text = element_text(size = 8), 
                strip.background = element_rect(fill = "white")) +
          scale_y_continuous(labels = function(x) format(x, scientific = TRUE),
                             breaks = NULL) +
          scale_color_manual(values = c("dodgerblue3", "black", "red"))
      )
    }
  }
  return(data_export) 
}  


#' Evaluation of calibration curves
#' 
#' Evaluation of calibration curves for each nucleotide and defined transitions. 
#' This function checks the following parameter: (i) noise level and (ii) saturation.
#' Corresponding tags are evaluated and added to the data frame, that is also exported
#' as a .csv file at the end of the function. 
#' 
#' Generated parameter and tags are explained in greater detail below.
#' 
#' @param cal_data  Dataframe, in ideal case generated by the function import_files(mode = "cal")
#' @param path_files path, defining export folder within the .Rproj-folder
#' 
#' @return dataframe containing tags with corresponding information.
#' 
#' @export
evaluate_calibrations <- function(cal_data, eval_trueblank = TRUE, 
                                  true_blank = "TrueBlank", 
                                  excl_below_tb = TRUE,
                                  eval_saturation = FALSE, eval_level = "top2",
                                  excl_saturated = FALSE,
                                  incl_plot = TRUE, path_files = "output/", ...) {
  data_export = cal_data
  
  if (eval_trueblank == TRUE) { #### TRUE-BLANK - $tag_noise---@param: true_blank
    
    ###### calc mean-val for true blank, unique values
    tb_mean = subset(data_export, data_export$calcurve == true_blank)
    
    tb_mean = ddply(tb_mean, c("nuc_id", "nuc_group" ,"transition_id"), transform, 
                    n_tb_val = length(median_intensity), 
                    mean_tb_val = mean(median_intensity),
                    sd_tb_val = sd(median_intensity))
    
    tb_mean = unique(tb_mean[, c("nuc_id", "nuc_group" ,"transition_id", "mean_tb_val")])
    
    
    ###### merge: true-blank values and input data
    data_values = merge(data_export, tb_mean)
    data_values = subset(data_values, data_values$calcurve != "TrueBlank")
    
    ###### Evaluate $noise: below or above true blank
    data_values$tag_noise = ifelse(data_values$median_intensity <= data_values$mean_tb_val, 
                                   "below_tb", "above_tb")
    
    data_export = data_values
    #end true blank
  }
  
  if (eval_saturation == TRUE) { #### SATURATION - $tag_saturation-- @param: saturation----------
    
    ##### select top2 levels and check for min of delta between mean-values(median_intensity)
    data_sat = subset(data_export, data_export$level >= 5)
    
    data_sat = ddply(data_sat, c("nuc_id", "nuc","nuc_group", "transition_id", "date" ,"level"), summarise, 
                     n_int = length(median_intensity),
                     mean_int = mean(median_intensity), 
                     sd_int = sd(median_intensity))
    
    ref_level10 = subset(data_sat, data_sat$level == 10)
    ref_level10 = unique(ref_level10[, c("nuc_id", "nuc" ,"date", "transition_id", "mean_int")])
    colnames(ref_level10)[grepl("mean_int", colnames(ref_level10))] <- "ref_l10_int"
    
    data_sat_m = merge(data_sat, ref_level10, all.x = TRUE)
    data_sat_m$ratio_5 = data_sat_m$mean_int / data_sat_m$ref_l10_int
    
    ### small freq table
    #freq_table = count(data_sat_m, vars = c("nuc"))
    
    #end saturation  
  }  else {
    data_fin = data_export
  }
  
  if (incl_plot == TRUE) {
    ###### plotting ------------------ @param: exclude_below_tb -------------------
    ######             @param: generate_plot
    
    data_plot = data_fin
    
    ### subsetting accord. to function call
    ### (1 - tag_noise)
    if (excl_below_tb == TRUE) {
      data_plot = subset(data_plot, data_plot$tag_noise != "below_tb")
      message("Done - excluded values below true blank levels!")
    } 
    
    ### (2 - tag_saturation)
    if (excl_saturated == TRUE) {
      data_plot = subset(data_plot, data_plot$tag_saturation != "saturated")
      message("Done - excluded saturated levels!")
    } 
    
    
    for (var in unique(data_plot$nuc_group)) {
      print(
        ggplot(subset(data_plot, data_plot$nuc_group == var), 
               aes(x = level, y = median_intensity, colour = factor(date))) + 
          geom_point() + 
          facet_grid(nuc ~ transition_id, scales = "free_y") + 
          geom_hline(aes(yintercept = mean_tb_val), color = "grey", linetype = 2) + 
          theme_bw() + 
          theme(axis.text.x = element_text(size = 6),
                axis.text.y = element_text(size = 8)) +
          ggtitle(paste0("Nucleotide (Calibration): ", var)) +
          theme(strip.text = element_text(size = 8), 
                strip.background = element_rect(fill = "white")) +
          scale_y_continuous(labels = function(x) format(x, scientific = TRUE),
                             breaks = NULL) +
          scale_color_manual(values = c("dodgerblue3", "black", "red"))
      )
    }
    
    
    #end plot  
  } 
  
  #end function    
}


#' Graphical output of calibration curves
#' 
#' This function generated decent ggplot2 graphics for the evaluation
#' of calibration curves. Depending on the presence of tags, e.g., tag_noise or 
#' tag_saturation, plots visualise corresponding content.
#' 
#' @param cal_data 
#' 
#' @return Plot object that can be printed
#' 
#plot_calibrations <- function(cal_data, ...) {
#  
#  
#}