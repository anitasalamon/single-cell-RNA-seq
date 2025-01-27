---
title: "scRNA-seq analysis for manuscript: Global Inhibition of Myeloperoxidase Improves Survival in a Novel Mouse Model of Coronary Atherosclerosis, Spontaneous Myocardial Infarction, and Stroke"
author: "Anita Salamon"
date: '2022-15-09'
output:
  pdf_document: default
  html_document: default
---
# **step: QC Filter Cells**

## Intruction 
This notebook provides an overview of the scRNA-seq analysis workflow for the manuscript in preparation for submission at *Nature* in 2023

![Workflow showing the steps necessary to get single cell isolation from advanced BCA lesions \label{figurelabel}](/project/Owens_Rivanna/01.Data_Analysis/2020.SMC.PDGF.ENDO.IL1B.Alex.Vlad.Ricky/2020.03.v1.analysis/04.figures.and.logos/Picture1.png)

## Experimental Design 
SMC lineage tracing Myh11-Cre^ERT2^/Rosa-eYFP/*SR-B1*^$\Delta CT$/$\Delta CT$^/LDLR^-/-^ mice treated AZM198 for 24 weeks on WD vs 24 weeks WD control. 
First, let's load the necessary packages for the analysis. For installation, please refer to package instructions.
```{r loading-datasets, include=FALSE}
.libPaths("/project/Owens_Rivanna/RStudio_lib/4.1")
library(magrittr)
library(rmarkdown)
library(Seurat)
library(hdf5r)
library(knitr)
library(kableExtra)
library(ggplot2)
library(dplyr)
library(reshape2)
library(biomaRt)
library(limma)
library(topGO)
library(org.Hs.eg.db)
library(sva)
library(scran)
```
The following code block sets three variables that you must update to run this code successfully on your own experiment. These variables determine what your experiment is named and where R looks for the Cell Ranger output.
The “ids” variable should be your sample names and **must** be the names of directories that contain the “outs” folders created by Cell Ranger.
```{r }
experiment_name = "AZM"
dataset_loc <- "/project/Owens_Rivanna/01.Data_Analysis/2022.09.scRNA-seq_Sohel/"
ids <- c("WT_ALL", "AZM_ALL", "WT_YFP", "AZM_YFP")
```
## Sequencing metrics
Summary metrics for each sample, similar output to what Cell Ranger generates but show all libraries together.
```{r}
d10x.metrics <- lapply(ids, function(i){
  metrics <- read.csv(file.path(dataset_loc, paste0(i,"_CountMatrix/outs"),"metrics_summary.csv"), colClasses = "character")
})
experiment.metrics <- do.call("rbind", d10x.metrics)
rownames(experiment.metrics) <- ids

sequencing.metrics <- data.frame(t(experiment.metrics[,c(1:19)]))
rownames(sequencing.metrics) <- gsub("\\.", " ", rownames(sequencing.metrics))

sequencing.metrics %>%
  kable(caption = "<center> <b> Cell Ranger Results </b>") %>%
  pack_rows("Overview", 1, 3, label_row_css = "background-color: #666; color: #fff;") %>%
  pack_rows("Sequencing Characteristics", 4, 9, label_row_css = "background-color: #666; color: #fff;") %>%
  pack_rows("Mapping Characteristics", 10, 19, label_row_css = "background-color: #666; color: #fff;") %>%
  kable_classic_2()
```
## Load the Cell Ranger Matrix Data 
To use the Cell Ranger defined cells, changed “raw_feature_bc_matrix.h5” to “filtered_feature_bc_matrix.h5”. Here, I am using the raw data.
```{r}
d10x.data <- lapply(ids, function(i){
  d10x <- Read10X_h5(file.path(dataset_loc, paste0(i, "_CountMatrix/outs"),"raw_feature_bc_matrix.h5"))
  colnames(d10x) <- paste(sapply(strsplit(colnames(d10x),split="-"),'[[',1L),i,sep="-")
  d10x
})
names(d10x.data) <- ids
```
## Let's recreate the barcode rank plot from the Cell Ranger web summary file.
Barcode Rank Plot for the gene expression data enables one to assess library quality. Ideally there is a steep drop-off separating high UMI count cells from low UMI count background noise.
```{r}
plot_cellranger_cells <- function(ind){
  xbreaks = c(1,1e1,1e2,1e3,1e4,1e5,1e6)
  xlabels = c("1","10","100","1000","10k","100K","1M")
  ybreaks = c(1,2,5,10,20,50,100,200,500,1000,2000,5000,10000,20000,50000,100000,200000,500000,1000000)
  ylabels = c("1","2","5","10","2","5","100","2","5","1000","2","5","10k","2","5","100K","2","5","1M")

  pl1 <- data.frame(index=seq.int(1,ncol(d10x.data[[ind]])),
                    nCount_RNA = sort(Matrix:::colSums(d10x.data[[ind]])+1,decreasing=T),
                    nFeature_RNA = sort(Matrix:::colSums(d10x.data[[ind]]>0)+1,decreasing=T)) %>%
    ggplot() +
    scale_color_manual(values=c("red2","blue4"), labels=c("Features", "UMI"), name=NULL) +
    ggtitle(paste("CellRanger filltered cells:",ids[ind],sep=" ")) + xlab("Barcodes") + ylab("counts (UMI or Features") +
    scale_x_continuous(trans = 'log2', breaks=xbreaks, labels = xlabels) +
    scale_y_continuous(trans = 'log2', breaks=ybreaks, labels = ylabels) +
    geom_line(aes(x=index, y=nCount_RNA, color = "UMI"), size=1.75) +
    geom_line(aes(x=index, y=nFeature_RNA, color = "Features"), size=1.25)

  return(pl1)
}
plot_cellranger_cells(1)
plot_cellranger_cells(2)
plot_cellranger_cells(3)
plot_cellranger_cells(3)
```
## Create Seurat Object
```{r}
#combine list 
experiment.data <- do.call("cbind", d10x.data)
## Basic filtering. Filter criteria: remove genes that do not occur in a minimum of 0 cells and remove cells that don’t have a minimum of 300 features
 experiment.aggregate <- CreateSeuratObject(
  experiment.data,
  project = experiment_name,
  min.cells = 0,
  min.features = 300,
  names.field = 2,
  names.delim = "\\-")
str(experiment.aggregate)
#Lets spend a little time getting to know the Seurat object
slotNames(experiment.aggregate)
head(experiment.aggregate[[]])
str(d10x.data)
str(experiment.data)
tail(colnames(experiment.data))
```

## Calculate percentage of mitochondrial transcripts
```{r}
experiment.aggregate$percent.mito <- PercentageFeatureSet(experiment.aggregate, pattern = "^mt-")
summary(experiment.aggregate$percent.mito)
```

## Calculate percentage of hemoglobin transcripts
```{r}
experiment.aggregate$percent.hemo <- PercentageFeatureSet(experiment.aggregate, pattern = "^Hb[^(p)]")
summary(experiment.aggregate$percent.hemo)
```

## Basic QA/QC
Let’s examine the distribution of features (genes) per cell, number of UMIs per cell, and percent mitochondrial and hemoglobin reads per cell in each of the samples
### Quantile tables
```{r}
kable(do.call("cbind", tapply(experiment.aggregate$nFeature_RNA, 
                      Idents(experiment.aggregate),quantile,probs=seq(0,1,0.05))),
      caption = "<center> <b> 5% Quantiles of Genes/Cell by Sample </b>") %>% kable_classic_2()
```

```{r}
kable(do.call("cbind", tapply(experiment.aggregate$nCount_RNA, 
                                      Idents(experiment.aggregate),quantile,probs=seq(0,1,0.05))),
      caption = "<center> <b> 5% Quantiles of UMI/Cell by Sample </b>") %>% kable_classic_2()
```

```{r}
kable(round(do.call("cbind", tapply(experiment.aggregate$percent.mito, Idents(experiment.aggregate),quantile,probs=seq(0,1,0.05))), digits = 3),
      caption = "<center> <b> 5% Quantiles of Percent Mitochondria by Sample </b>") %>% kable_classic_2()
```

```{r}
kable(do.call("cbind", tapply(experiment.aggregate$percent.hemo, 
                                      Idents(experiment.aggregate),quantile,probs=seq(0,1,0.05))),
      caption = "<center> <b> 5% Quantiles of Percent Hemoglobin by Sample </b>") %>% kable_classic_2()
```
## Violin Plots of 1) number of genes, 2) number of UMI, 3) percent mitochondrial genes and 4) percent hemoglobin genes
```{r}
VlnPlot(
  experiment.aggregate,
  features = c("nFeature_RNA", "nCount_RNA","percent.mito", "percent.hemo"),
  ncol = 2, pt.size = 0.3)
```
## Ridge Plot of 1) number of genes, 2) number of UMI, 3) percent mitochondrial genes and 4) percent hemoglobin genes
```{r}
RidgePlot(experiment.aggregate, features=c("nFeature_RNA","nCount_RNA", "percent.mito", "percent.hemo"), ncol = 1)
```
## Scatter plot of gene expression across cells, (colored by sample), drawing horizontal and verticale lines at proposed filtering cutoffs.
```{r}
png(file=".png",
width=600, height=350)
FeatureScatter(experiment.aggregate,
               feature1 = "nCount_RNA",
               feature2 = "nFeature_RNA",
               shuffle = TRUE) +
    geom_hline(yintercept = c(420,5800), linetype = 2, color="blue")
```

```{r}
  FeatureScatter(experiment.aggregate,
               feature1 = "nFeature_RNA",
               feature2 = "percent.mito",
               shuffle = TRUE) +
    geom_hline(yintercept = 15, linetype = 2, color="blue") +
   geom_vline(xintercept = c(420,5800), linetype = 2, color="blue" )
```

```{r}
FeatureScatter(experiment.aggregate,
               feature1 = "nFeature_RNA",
               feature2 = "percent.hemo",
               shuffle = TRUE) +
  geom_hline(yintercept = 5, linetype = 32, color="blue")
```
how many cells before QC selection?
```{r}
table(experiment.aggregate$orig.ident)
```
## QC selection:
-We define poor quality samples for mitochondrial content as cells which has more than 15% of cell reads originating from the mitochondrial genes and more than 5% of hemoglobin genes
-We selected the cut-offs of removing genes below 5th percentile and genes above 95th percentile


```{r}
experiment.aggregate.Anita <- experiment.aggregate
#these filtering cutoffs are a bit arbitrary and it might be different for different dataset, cell lines etc. 
experiment.aggregate.Anita <- subset(experiment.aggregate, percent.mito <= 15.0)
experiment.aggregate.Anita <- subset(experiment.aggregate.Anita, percent.hemo <= 5.0)
experiment.aggregate.Anita <- subset(experiment.aggregate.Anita, nFeature_RNA >= 420 & nFeature_RNA <= 5800)
experiment.aggregate.Anita
#how many cells after QC selection?
table(experiment.aggregate.Anita$orig.ident)
```
## Explore plots after filtering
```{r}
VlnPlot(
  experiment.aggregate.Anita,
  features = c("nFeature_RNA", "nCount_RNA","percent.mito", "percent.hemo"),
  ncol = 2, pt.size = 0.3)
```
## Ridge plot after QC selection
```{r}
RidgePlot(experiment.aggregate.Anita, features=c("nFeature_RNA","nCount_RNA", "percent.mito", "percent.hemo"), ncol = 1)
```
## Finally, save the Seurat object and view the object.
```{r}
save(experiment.aggregate.Anita,file="pre_sample_corrected-Anita.RData")
```

## Session Information
```{r}
sessionInfo()
```

