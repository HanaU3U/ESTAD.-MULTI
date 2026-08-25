dataset <- read.csv("DATASET/cleaned_hourly_data.csv")

head(dataset)
str(dataset)
summary(dataset)

install.packages("corrplot")
library(corrplot)


install.packages("dplyr")

library(dplyr)
library(corrplot)

dataset_num <- dataset %>%
  mutate(across(where(is.character), ~ as.numeric(as.factor(.))))

dataset_num <- dataset %>%
  select(-id, -name, -full_name, -owner, -description, -is_fork, -html_url, -homepage) %>%
  mutate(across(where(is.character), ~ as.numeric(as.factor(.))))

# Verificar estructura
str(dataset_num)

# Revisar cuántos NA quedaron (importante en este dataset)
colSums(is.na(dataset_num))

# Matriz de correlación (pairwise.complete.obs maneja los NA)
matriz_cor <- cor(dataset_num, use = "pairwise.complete.obs")
round(matriz_cor, 2)


corrplot(matriz_cor, 
         method = "color", 
         type = "upper", 
         tl.col = "black", 
         tl.srt = 45,
         tl.cex = 0.6,
         addCoef.col = "black",
         number.cex = 0.4)

corrplot(matriz_cor)



# Seleccionar únicamente variables numéricas
dataset_numeric <- dataset[sapply(dataset, is.numeric)]

# Quitar id
dataset_numeric <- dataset_numeric[, !names(dataset_numeric) %in% "id"]

# Quitar stars
dataset_numeric <- dataset_numeric[, !names(dataset_numeric) %in% "stars"]

# Matriz de correlación de Spearman
dataset.cor <- cor(dataset_numeric,
                   method = "spearman",
                   use = "complete.obs")

dataset.cor

# Gráfico
corrplot(dataset.cor,
         method = "color",
         type = "upper",
         addCoef.col = "black",
         tl.col = "black",
         tl.srt = 45)

corrplot(dataset.cor)

install.packages("Hmisc")
library("Hmisc")


dataset.rcorr = rcorr(as.matrix(dataset))
dataset.rcorr


head(dataset2)
str(dataset2)
summary(dataset2)