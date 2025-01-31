#' read_input
#'
#' @param file, String, Input file name
#' @param delimiter, String, delimiter
#' @param header, Logical, if using the first line as header
#' @param count_field_num, num, num of count column in the file
#' @return
#' @export read_input
#'
#' @examples
#' read_input(file)
read_input=function(file,delimiter="\t",header=F,count_field_num=2){
  df_out=read.table(file,sep = delimiter,stringsAsFactors = F,header=header)
  df_out=df_out[c(1,count_field_num)]
  names(df_out)=c("feature","TestSample")
  df_out
}


#' load_data
#'
#' @param label
#'
#' @return
#' @export
#'
#' @examples
load_data=function(label="obj_234_HTSeqCount"){
  if(label=="obj_234_HTSeqCount"){
    out=  readRDS("data-raw/obj_234_HTSeqCountMini.rds")
  }

  if(label=="obj_2042_HTSeqCount"){
    out=  readRDS("data-raw/obj_2042_HTSeqCountMini.rds")
  }

  out
}


#' f_imputation
#'
#' @param obj_ref
#' @param assay_name_in
#' @param df_in
#' @param method
#'
#' @return
#' @export
#'
#' @examples
f_imputation=function(obj_ref,assay_name_in="keyFeatures",df_in,method="randomforest"){
  features_in=obj_ref[[assay_name_in]]

  feature_overlap=features_in[features_in %in% df_in$feature]

  if(all(features_in %in% feature_overlap)){
    message("\nAll features found, no need to do imputation.")
    df_out=df_in}

  if(!all(features_in %in% feature_overlap)){
    message(paste0("\n",length(features_in)-length(feature_overlap)," of the ",length(features_in)," Key genes missing."))
    df_ref=as.data.frame(assays(obj_ref$SE)[["vst"]])
    df_ref=df_ref[features_in,]
    df_ref$feature=row.names(df_ref)

    df_for_imp=df_ref %>% left_join(df_in)
    row.names(df_for_imp)=df_for_imp$feature

    if(method=="randomforest"){
      message("\nImputation using randomforest")
      df_for_imp$feature=NULL

      imputed_data = missForest::missForest(df_for_imp)

      imputed_data_matrix = imputed_data$ximp
      imputed_data_matrix$feature=row.names(df_for_imp)

      df_out=imputed_data_matrix[names(df_in)]
    }
    df_out
  }
  df_out
}


#' obj_merge
#'
#' @param obj_in , object, object of reference
#' @param file_obj , string, file of object of reference
#' @param df_in , dataframe, count dataframe for merge
#'
#' @return
#' @export obj_merge
#'
#' @examples
#' obj_x=obj_merge(file_obj = "../tsne/234_featureCounts/obj_234_featureCountsMini.rds",df_in = df_counts)
obj_merge=function(obj_in=NULL,file_obj=NULL,df_in,assay_name_in="vst"){
  if(!is.null(file_obj)){
    obj_in=readRDS(file_obj)
  }

  df_in=as.data.frame(df_in)

  #check name overlapping
  if(names(df_in)[2] %in% colnames(obj_in$SE)){
    obj_in$SE=obj_in$SE[,-match(names(df_in)[2],colnames(obj_in$SE))]
  }

  #get obj count data
  count_ref=assays(obj_in$SE)[[assay_name_in]]
  count_ref=as.data.frame(count_ref)
  count_ref$feature=row.names(count_ref)

  #check overlapped sample ID
  id_overlap=names(count_ref)[names(count_ref) %in% names(df_in)]
  id_overlap=id_overlap[!id_overlap =="feature"]
  if(length(id_overlap)>=1){
    message(paste0("Overlapped sample ID(s): ",paste0(id_overlap,collapse = ", "),"\n"))
    count_ref[id_overlap]=NULL}

  id_in_ref=names(count_ref)[!names(count_ref)=="feature"]

  #get merged count data

  if(!any(grepl("feature",names(df_in)))){df_in$feature=row.names(df_in)}

  features_overlap=df_in$feature[df_in$feature %in% row.names(count_ref)]
  count_merge=df_in %>% left_join(count_ref) %>%
    filter(feature %in% features_overlap)
  row.names(count_merge)=count_merge$feature
  count_merge$feature=NULL

  #get info data
  df_info_ref=as.data.frame(colData(obj_in$SE[,id_in_ref]))

  df_info_in=data.frame(
    id=names(df_in)[2:ncol(df_in)],
    diag="TestSample",
    diag_raw="TestSample",
    diag_raw1="TestSample",

    library="Unknown"
  )

  row.names(df_info_in)=names(df_in)[2:ncol(df_in)]

  df_info_all=bind_rows(df_info_in,df_info_ref)[c("diag","diag_raw","diag_raw1")]

  #get output obj
  if(all(names(count_merge)==row.names(df_info_all))){
    matrix_list=list(counts=count_merge)
    names(matrix_list)=assay_name_in
    SE=SummarizedExperiment(assays=matrix_list, colData = df_info_all)
    obj_out=obj_in
    obj_out$SE=SE
  }

  if(!all(names(count_merge)==row.names(df_info_all))){
    stop("Names not match")
  }
  obj_out
}

#' get_geneExpression
#'
#' @param df_vst
#' @param genes
#'
#' @return
#' @export
#'
#' @examples
get_geneExpression=function(df_vst,genes){
  names(df_vst)=c("feature","TestSample")
  geneId=info_gtf_hg38$gene_id[info_gtf_hg38$gene_name %in% genes]
  out=df_vst[df_vst$feature %in% geneId,] %>%
    left_join(info_gtf_hg38 %>%
                transmute(feature=gene_id,Gene=gene_name)) %>%
    mutate(Expression = TestSample) %>%
    select(Gene,Expression)
  out
}


#' get_features_df
#'
#' @param obj_in
#' @param assay_name_in
#' @param features
#'
#' @return
#' @export
#'
#' @examples
get_features_df=function(obj_in,assay_name_in="vst",features="cluster_Phenograph_pca1"){
  features1=features[features %in% names(colData(obj_in$SE))]
  if(length(features1) >=1){
    df_feature1=as.data.frame(colData(obj_in$SE)[features1])
    df_feature=df_feature1
  }

  features2=features[features %in% rownames(obj_in$SE)]
  if(length(features2) >=1){
    df_feature2=as.data.frame(t(assays(obj_in$SE[features2,])[[assay_name_in]]))
    df_feature=df_feature2
  }

  if(length(features1) >=1 & length(features2) >=1){
    if(!all(row.names(df_feature1)==row.names(df_feature2))){stop("df feature rownames not match")}
    df_feature=bind_cols(df_feature1,df_feature2)
  }

  df_feature
}

#' get_embeding_feature
#'
#' @param obj_in
#' @param assay_name_in
#' @param features
#' @param reduction
#'
#' @return
#' @export
#'
#' @examples
get_embeding_feature=function(obj_in,assay_name_in="vst",features="cluster_Phenograph_pca1",reduction="tsne"){
  if(!all(row.names(colData(obj_in$SE))==row.names(obj_in[reduction]))){stop("Sample names in colData and reduction not match")}

  df_feature=get_features_df(obj_in = obj_in,assay_name_in = assay_name_in,features = features)

  df_reduction=obj_in[[reduction]]
  df_out=bind_cols(df_feature,df_reduction)

  df_out
}

#' get_cols_cat
#'
#' @param value
#' @param cols_in
#' @param cols_in_default
#'
#' @return
#' @export
#'
#' @examples
get_cols_cat=function(value,cols_in,cols_in_default){
  if(!any(names(cols_in) %in% value)){
    print("Supplied color labels not inclued in values levels, use default cols instead")
    if(length(unique(value))>  length(cols_in_default)){message("Defaule color number not enough, the rest will using grey")}
    cols_out=cols_in_default[1:length(unique(value))]
    names(cols_out)=sort(unique(value))
  }

  if(any(names(cols_in) %in% value)){
    cols_out=cols_in[names(cols_in) %in% value]
    if(length(cols_out)<length(levels(as.factor(value)))){
      cols_out=cols_in[1:length(levels(as.factor(value)))]
    }
  }
  cols_out
}


#' subtypeCol
#'
#' @return
#' @export
#'
#' @examples
subtypeCol=function(){
  subtypeCol=c()
  {
    subtypeCol["ETV6::RUNX1"]="gold2"
    subtypeCol["ETV6::RUNX1-like"]="pink"

    subtypeCol["Ph"]="magenta3"
    subtypeCol["Ph-like"]="red4"
    subtypeCol["Ph-like(CRLF2)"]="red4"

    subtypeCol["KMT2A"]="#1F78B5"
    subtypeCol["DUX4"]='grey40'
    subtypeCol["TCF3::PBX1"]="darkgoldenrod4"
    subtypeCol["ZNF384"]="#A8DD00"
    subtypeCol["MEF2D"]="#66C2A6"
    subtypeCol["BCL2/MYC"]="seagreen2"
    subtypeCol["NUTM1"]='black'
    subtypeCol["HLF"]= "skyblue"
    subtypeCol["ZEB2/CEBP"]="#D27B1C"
    subtypeCol["CDX2/UBTF"]="#E6BEFF"

    subtypeCol["Hyperdiploid"]="#3E9F32"
    subtypeCol["Low hypodiploid"]="#1E90FF"
    subtypeCol["NearHaploid"]='blue3'
    subtypeCol["Near haploid"]='blue3'
    subtypeCol["iAMP21"]="lightslateblue"

    subtypeCol["PAX5alt"]="#FFA620"
    subtypeCol["PAX5::ETV6"]="#808000"
    subtypeCol["PAX5(P80R)"]="orangered"
    subtypeCol["PAX5 P80R"]="orangered"
    subtypeCol["IKZF1(N159Y)"]="#CCCC33"
    subtypeCol["IKZF1 N159Y"]="#CCCC33"

    subtypeCol["CRLF2(non-Ph-like)"]='grey75'
    subtypeCol["KMT2A-like"]='grey75'
    subtypeCol["ZNF384-like"]='grey75'
    subtypeCol["Low hyperdiploid"]='grey75'
    subtypeCol["Other"]='grey75'

    subtypeCol["_Prediction"]="cyan"
    # subtypeCol["TestSample"]="cyan"


  }
  subtypeCol
}
