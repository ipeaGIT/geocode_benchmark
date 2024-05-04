suppressPackageStartupMessages({
  library(targets)
  library(tarchetypes)
  loadNamespace("sf")
})

# cnes_path <- tar_read(cnes_path)
preprocess_cnes <- function(cnes_path) {
  cnes <- readxl::read_xlsx(cnes_path, skip = 15)
  cnes <- dplyr::select(
    cnes,
    UF, MUNICIPIO = MUNICÍPIO, LOGRADOURO, NUMERO, BAIRRO, CEP
  )
  
  cnes <- enderecopadrao::padronizar_enderecos(
    cnes,
    campos_do_endereco = enderecopadrao::correspondencia_campos(
      logradouro = "LOGRADOURO",
      numero = "NUMERO",
      cep = "CEP",
      bairro = "BAIRRO",
      municipio = "MUNICIPIO",
      estado = "UF"
    )
  )
  
  cnes <- dplyr::mutate(
    cnes,
    logradouro_completo = ifelse(
      is.na(numero),
      logradouro,
      paste(logradouro, numero)
    )
  )
  
  return(cnes)
}

# locations <- tar_read(preprocessed_cnes)
# n_threads <- tar_read(n_threads)[1]
# n_rows <- tar_read(n_rows)[1]
calculate_processing_times <- function(locations, n_threads, n_rows) {
  reticulate::use_condaenv(
    "C://Program Files/ArcGIS/Pro/bin/Python/envs/arcgispro-py3"
  )
  
  address_fields <- geocodepro::address_fields_const(
    Address_or_Place = "logradouro_completo",
    Neighborhood = "bairro",
    City = "municipio",
    State = "estado",
    ZIP = "cep"
  )
  
  random_indices <- sample(1:nrow(locations), size = n_rows, replace = FALSE)
  
  sample_locations <- locations[random_indices]
  
  tictoc::tic()
  geocoded_cnes <- geocodepro::geocode(
    sample_locations,
    locator = paste0("C://StreetMap/NewLocators/BRA_", n_threads, "/BRA.loc"),
    address_fields = address_fields,
    cache = FALSE,
    verbose = FALSE
  )
  timing <- tictoc::toc()
  
  test_summary <- data.table::data.table(
    n_threads = n_threads,
    n_rows = n_rows,
    time = timing$toc - timing$tic
  )
  
  return(test_summary)
}

dummy_geocode_call <- function() {
  result <- reticulate::use_condaenv(
    "C://Program Files/ArcGIS/Pro/bin/Python/envs/arcgispro-py3"
  )
  
  locations <- data.frame(
    logradouro = "Avenida Venceslau Brás, 72",
    bairro = "Botafogo",
    cidade = "Rio de Janeiro",
    uf = "RJ",
    cep = "22290-140"
  )
  
  result <- geocodepro::geocode(
    locations,
    address_fields = geocodepro::address_fields_const(
      Address_or_Place = "logradouro",
      Neighborhood = "bairro",
      City = "cidade",
      State = "uf",
      ZIP = "cep"
    ),
    cache = FALSE,
    verbose = FALSE
  )
  
  return(result)
}

list(
  tar_target(a_dummy_geocode_call, dummy_geocode_call(), cue = tar_cue("always")),
  tar_target(
    cnes_path,
    "L://Proj_acess_oport/data-raw/cnes/2022/BANCO_ESTAB_IPEA_COMP_08_2022_DT_25_10_2023.xlsx",
    format = "file_fast"
  ),
  tar_target(preprocessed_cnes, preprocess_cnes(cnes_path)),
  tar_target(n_threads, c(10, 15, 20, 25, 28)),
  tar_target(n_rows, 100000),
  tar_target(n_samples, c(1:5)),
  tar_target(old_server_timings_path, "data/old_server_timings"),
  tar_target(new_server_timings_path, "data/new_server_timings"),
  tar_target(third_server_timings_path, "data/third_server_timings"),
  tar_target(fourth_server_timings_path, "data/fourth_server_timings"),
  tar_target(
    timings,
    calculate_processing_times(preprocessed_cnes, n_threads, n_rows),
    pattern = cross(n_threads, n_rows, n_samples),
    iteration = "list"
  ),
  tar_target(consolidated_timings, data.table::rbindlist(timings)),
  tar_render(readme, "README.Rmd", "README.md")
)