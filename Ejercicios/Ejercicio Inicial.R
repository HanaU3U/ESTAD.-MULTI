getwd()
3+4
2^10
sqrt(144)
(5+3)/2
x <- 10
y <- 3
x+y
x
edades <- c(19, 21, 20, 22, 19, 23, 21, 20)
length(edades)
numerico <- c(1.5, 2.7, 3.1)
caracter <- c("ana","Luis", "Carlos")
logico <- c(TRUE, FALSE, TRUE)
class(numerico)
class(caracter)
class(logico) # Tipo de dato
mezcla <- c(1, 2, "tres") #Pone todo al tipo mas general
class(mezcla)
edades[1] # Empieza a contar en 1 no en 0 los arrays
edades[c(1,3,5)] # LAs pos 1, 3 y 5
edades[-1] # Todas menos el primero
edades[edades>20] # Indexacion logica -> condiciones
edades +1 # Foreach implicito operaciones aplican a todo el vector
edades * 2
edades > 20
mean (edades) # Media
sd (edades) # Desviación estándar
var(edades)# Varianza
min(edades) # Valor Min
max(edades) # Valor Max
summary(edades) # Resumen Datos Estadisticos

con_faltante <- c(19, 21, NA, 22, 19)
mean(con_faltante) # Media con Valor faltante
mean(con_faltante, na.rm= TRUE) # Media sin valor faltante
is.na(con_faltante) # Imprime para el array que datos son NA
sum(is.na(con_faltante)) # Imprime la cantidad de NA


grupo <- factor(c("A", "B", "A", "C", "B", "A")) # Definir variables categoricas
grupo # Imprimir 
levels(grupo) # saber que categorias hay
table(grupo) # Tabla con contador de cuantas hay por level o categoria
class(iris$Species)
levels(iris$Species)

estudiantes <- data.frame(
  estudiante = c("Ana", "Luis", "Carlos", "Marta", "Sofia", "Pedro", "Laura", "Camilo"),
  edad = c(19, 21, 20, 22, 19, 23, 21, 20),
  promedio = c(4.5, 3.8, 4.0, 3.5, 4.7, 3.2, 4.1, 3.9),
  horas_estudio = c(15, 8, 10, 6, 18, 5, 11, 9),
  faltas = c(1, 5, 3, 6, 0, 8, 2, 4)
)

estudiantes
dim(estudiantes) # Saber n filas, p columnas
names(estudiantes) # Saber nombres de variables
str(estudiantes) # tipo de cada variable
summary(estudiantes) # Datos est Por columna
head(estudiantes, 3) # Muestra primeros datos ((, n) -> cantidad) de set
nrow(estudiantes) # cantidad de filas
ncol(estudiantes) # cantidad columnas -> "estudiante" es la etiqueta (no cuenta como var de analisis)

#Seleccionar columna
estudiantes$promedio
estudiantes[["promedio"]]
estudiantes[, "promedio"]

#Seleccionar General
#Notacion General df[fila, columna]
estudiantes[1,]# Prim fila
estudiantes[,2] # 2da col
estudiantes[1:3, c("edad", "promedio")] # De la 1 a la 3 edad y prom con etiquetas
estudiantes[estudiantes$promedio > 4,] #filtro por condicion



datos_num <- estudiantes[,c("edad", "promedio", "horas_estudio", "faltas")] # Sin contar etiqueta
dim(datos_num)# Sin contar etiqueta
colMeans(datos_num) # Media por columna
apply(datos_num, 2, sd) # Desviacion estandar por columna
cor(datos_num) # Matriz de correlacion, resume relaciones objeto multivariante

m <- matrix(1:6, nrow = 2, ncol = 3)   # matriz: todo del mismo tipo
m
dim(m)
lista <- list(nombre = "Ana", notas = c(4.5, 3.8), aprobo = TRUE)
lista$notas
