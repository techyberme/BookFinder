"""Madrid Public Libraries Geo Data & Proximity Utilities.

Contains coordinates (lat, lon), district/municipality, and normalized name matching
for Community of Madrid and Ayuntamiento de Madrid library branches.
"""

import math
import re
import unicodedata
from typing import Dict, List, Optional, Tuple


# Master database of Madrid library branches with geographic coordinates
MADRID_LIBRARIES_DB: Dict[str, dict] = {
    # --- Red de Bibliotecas de la Comunidad de Madrid (BP) & Centrales ---
    "manuel_alvar": {
        "id": "manuel_alvar",
        "name": "Biblioteca Pública Central - Manuel Alvar",
        "aliases": ["manuel alvar", "bp manuel alvar", "salamanca bp manuel alvar", "salamanca. bp manuel alvar"],
        "lat": 40.4358,
        "lon": -3.6667,
        "district": "Salamanca",
        "municipality": "Madrid",
        "address": "Calle de Azcona, 42, 28028 Madrid",
    },
    "joaquin_leguina": {
        "id": "joaquin_leguina",
        "name": "Biblioteca Regional de Madrid Joaquín Leguina",
        "aliases": ["biblioteca regional", "joaquin leguina", "regional joaquin leguina", "biblioteca regional de madrid"],
        "lat": 40.3995,
        "lon": -3.6934,
        "district": "Arganzuela",
        "municipality": "Madrid",
        "address": "Calle de Ramírez de Prado, 3, 28045 Madrid",
    },
    "jose_acuna": {
        "id": "jose_acuna",
        "name": "Biblioteca Pública José Acuña (Moncloa)",
        "aliases": [
            "jose acuna", "jose acuña", "bp jose acuna", "bp jose acuña", "acuna", "acuña", "bp acuna", "bp acuña",
            "moncloa-aravaca. bp acuña", "moncloa-aravaca bp acuña", "moncloa bp acuña", "moncloa. bp acuña",
            "moncloa. bp acuna", "biblioteca publica jose acuna", "biblioteca pública josé acuña"
        ],
        "lat": 40.4284,
        "lon": -3.7175,
        "district": "Moncloa-Aravaca",
        "municipality": "Madrid",
        "address": "Calle Quintana, 9, 28008 Madrid",
    },
    "antonio_mingote": {
        "id": "antonio_mingote",
        "name": "BP Antonio Mingote (Latina)",
        "aliases": ["antonio mingote", "bp antonio mingote", "latina bp antonio mingote", "latina. bp antonio mingote"],
        "lat": 40.3846,
        "lon": -3.7663,
        "district": "Latina",
        "municipality": "Madrid",
        "address": "Calle Rafael Finat, 51, 28044 Madrid",
    },
    "damaso_alonso": {
        "id": "damaso_alonso",
        "name": "BP Dámaso Alonso (Chamartín)",
        "aliases": ["damaso alonso", "bp damaso alonso", "chamartin bp damaso alonso", "chamartin. bp damaso alonso", "chamartín. bp dámaso alonso"],
        "lat": 40.4632,
        "lon": -3.6766,
        "district": "Chamartín",
        "municipality": "Madrid",
        "address": "Calle de Manuel Ferrero, 1, 28036 Madrid",
    },
    "elena_fortun": {
        "id": "elena_fortun",
        "name": "BP Elena Fortún (Retiro)",
        "aliases": ["elena fortun", "bp elena fortun", "retiro bp elena fortun", "retiro. bp elena fortun", "retiro. bp elena fortún"],
        "lat": 40.4137,
        "lon": -3.6738,
        "district": "Retiro",
        "municipality": "Madrid",
        "address": "Calle del Doctor Esquerdo, 189, 28007 Madrid",
    },
    "fuencarral_rafael_alberti": {
        "id": "fuencarral_rafael_alberti",
        "name": "BP Rafael Alberti (Fuencarral)",
        "aliases": ["rafael alberti", "bp rafael alberti", "fuencarral bp rafael alberti", "fuencarral. bp rafael alberti", "fuencarral-el pardo. bp rafael alberti"],
        "lat": 40.4811,
        "lon": -3.7058,
        "district": "Fuencarral-El Pardo",
        "municipality": "Madrid",
        "address": "Calle Sangenjo, 38, 28034 Madrid",
    },
    "jose_hierro": {
        "id": "jose_hierro",
        "name": "BP José Hierro (Usera)",
        "aliases": ["jose hierro", "bp jose hierro", "usera bp jose hierro", "usera. bp jose hierro", "usera. bp josé hierro"],
        "lat": 40.3853,
        "lon": -3.7077,
        "district": "Usera",
        "municipality": "Madrid",
        "address": "Avenida de Rafaela Ybarra, 43, 28026 Madrid",
    },
    "jose_luis_sampedro": {
        "id": "jose_luis_sampedro",
        "name": "BP José Luis Sampedro (Chamberí)",
        "aliases": ["jose luis sampedro", "bp jose luis sampedro", "chamberi bp jose luis sampedro", "chamberi. bp jose luis sampedro", "chamberí. bp josé luis sampedro"],
        "lat": 40.4389,
        "lon": -3.7072,
        "district": "Chamberí",
        "municipality": "Madrid",
        "address": "Calle Felipe el Hermoso, 4, 28010 Madrid",
    },
    "jose_saramago": {
        "id": "jose_saramago",
        "name": "BP José Saramago (Fuencarral)",
        "aliases": ["jose saramago", "bp jose saramago", "fuencarral-el pardo bp jose saramago", "fuencarral-el pardo. bp josé saramago", "fuencarral. bp jose saramago"],
        "lat": 40.4728,
        "lon": -3.7075,
        "district": "Fuencarral-El Pardo",
        "municipality": "Madrid",
        "address": "Avenida del Monforte de Lemos, 38, 28029 Madrid",
    },
    "la_chata": {
        "id": "la_chata",
        "name": "BP La Chata (Carabanchel)",
        "aliases": ["la chata", "bp la chata", "carabanchel bp la chata", "carabanchel. bp la chata"],
        "lat": 40.3856,
        "lon": -3.7439,
        "district": "Carabanchel",
        "municipality": "Madrid",
        "address": "Calle General Ricardos, 252, 28025 Madrid",
    },
    "luis_rosales": {
        "id": "luis_rosales",
        "name": "BP Luis Rosales (Carabanchel)",
        "aliases": ["luis rosales", "bp luis rosales", "carabanchel bp luis rosales", "carabanchel. bp luis rosales"],
        "lat": 40.3842,
        "lon": -3.7481,
        "district": "Carabanchel",
        "municipality": "Madrid",
        "address": "Calle Antonia Rodríguez Sacristán, 7, 28044 Madrid",
    },
    "luis_martin_santos": {
        "id": "luis_martin_santos",
        "name": "BP Luis Martín-Santos (Villa de Vallecas)",
        "aliases": ["luis martin-santos", "luis martin santos", "bp luis martin santos", "villa de vallecas bp luis martin-santos", "villa de vallecas. bp luis martín-santos"],
        "lat": 40.3789,
        "lon": -3.6192,
        "district": "Villa de Vallecas",
        "municipality": "Madrid",
        "address": "Plaza Antonio María Segovia, 2, 28031 Madrid",
    },
    "maria_moliner": {
        "id": "maria_moliner",
        "name": "BP María Moliner (Villaverde)",
        "aliases": ["maria moliner", "bp maria moliner", "villaverde bp maria moliner", "villaverde. bp maría moliner"],
        "lat": 40.3475,
        "lon": -3.7121,
        "district": "Villaverde",
        "municipality": "Madrid",
        "address": "Calle Villalonso, 16, 28021 Madrid",
    },
    "miguel_hernandez": {
        "id": "miguel_hernandez",
        "name": "BP Miguel Hernández (Puente de Vallecas)",
        "aliases": ["miguel hernandez", "bp miguel hernandez", "puente de vallecas bp miguel hernandez", "puente de vallecas. bp miguel hernández"],
        "lat": 40.3905,
        "lon": -3.6528,
        "district": "Puente de Vallecas",
        "municipality": "Madrid",
        "address": "Avenida Rafael Alberti, 36, 28018 Madrid",
    },
    "moratalaz": {
        "id": "moratalaz",
        "name": "BP Moratalaz",
        "aliases": ["moratalaz", "bp moratalaz", "moratalaz bp moratalaz", "moratalaz. bp moratalaz"],
        "lat": 40.4072,
        "lon": -3.6496,
        "district": "Moratalaz",
        "municipality": "Madrid",
        "address": "Calle Corregidor Diego de Valderrábano, 24, 28030 Madrid",
    },
    "pedro_salinas": {
        "id": "pedro_salinas",
        "name": "BP Pedro Salinas (Centro)",
        "aliases": ["pedro salinas", "bp pedro salinas", "centro bp pedro salinas", "centro. bp pedro salinas"],
        "lat": 40.4082,
        "lon": -3.7118,
        "district": "Centro",
        "municipality": "Madrid",
        "address": "Glorieta de Puerta de Toledo, 1, 28005 Madrid",
    },
    "ruiz_egea": {
        "id": "ruiz_egea",
        "name": "BP Ruiz Egea (Chamberí)",
        "aliases": ["ruiz egea", "bp ruiz egea", "chamberi bp ruiz egea", "chamberi. bp ruiz egea", "chamberí. bp ruiz egea"],
        "lat": 40.4468,
        "lon": -3.7088,
        "district": "Chamberí",
        "municipality": "Madrid",
        "address": "Calle de Raimundo Fernández Villaverde, 6, 28003 Madrid",
    },
    "vallecas": {
        "id": "vallecas",
        "name": "BP Vallecas",
        "aliases": ["vallecas", "bp vallecas", "puente de vallecas bp vallecas", "puente de vallecas. bp vallecas"],
        "lat": 40.3952,
        "lon": -3.6685,
        "district": "Puente de Vallecas",
        "municipality": "Madrid",
        "address": "Calle Puerto de Monasterio, 9, 28053 Madrid",
    },
    "paco_rabal": {
        "id": "paco_rabal",
        "name": "BP Paco Rabal (Puente de Vallecas)",
        "aliases": ["paco rabal", "bp paco rabal", "puente de vallecas bp paco rabal", "puente de vallecas. bp paco rabal"],
        "lat": 40.3882,
        "lon": -3.6622,
        "district": "Puente de Vallecas",
        "municipality": "Madrid",
        "address": "Calle Felipe de Diego, 11, 28018 Madrid",
    },
    "portazgo": {
        "id": "portazgo",
        "name": "BP Portazgo (Puente de Vallecas)",
        "aliases": ["portazgo", "bp portazgo", "puente de vallecas bp portazgo", "puente de vallecas. bp portazgo"],
        "lat": 40.3922,
        "lon": -3.6585,
        "district": "Puente de Vallecas",
        "municipality": "Madrid",
        "address": "Calle Puerto de Somport, 2, 28038 Madrid",
    },
    "villaverde": {
        "id": "villaverde",
        "name": "BP Villaverde",
        "aliases": ["villaverde", "bp villaverde", "villaverde bp villaverde", "villaverde. bp villaverde"],
        "lat": 40.3541,
        "lon": -3.6987,
        "district": "Villaverde",
        "municipality": "Madrid",
        "address": "Calle de San Jenaro, 3, 28021 Madrid",
    },

    # --- Red de Bibliotecas del Ayuntamiento de Madrid (BM / BP Municipales) ---
    "eugenio_trias": {
        "id": "eugenio_trias",
        "name": "BP Eugenio Trías (Retiro)",
        "aliases": ["eugenio trias", "bp eugenio trias", "retiro bp eugenio trias", "retiro. bp eugenio trías", "eugenio trías"],
        "lat": 40.4158,
        "lon": -3.6791,
        "district": "Retiro",
        "municipality": "Madrid",
        "address": "Paseo Fernán Núñez, 24 (Parque de El Retiro), 28009 Madrid",
    },
    "ivan_de_vargas": {
        "id": "ivan_de_vargas",
        "name": "BP Iván de Vargas (Centro)",
        "aliases": ["ivan de vargas", "bp ivan de vargas", "centro bp ivan de vargas", "centro. bp iván de vargas", "iván de vargas"],
        "lat": 40.4139,
        "lon": -3.7107,
        "district": "Centro",
        "municipality": "Madrid",
        "address": "Calle de San Justo, 5, 28005 Madrid",
    },
    "conde_duque": {
        "id": "conde_duque",
        "name": "BP Conde Duque (Centro)",
        "aliases": ["conde duque", "bp conde duque", "centro bp conde duque", "centro. bp conde duque"],
        "lat": 40.4277,
        "lon": -3.7108,
        "district": "Centro",
        "municipality": "Madrid",
        "address": "Calle Conde Duque, 9-11, 28015 Madrid",
    },
    "mario_vargas_llosa": {
        "id": "mario_vargas_llosa",
        "name": "BP Mario Vargas Llosa (Centro)",
        "aliases": ["mario vargas llosa", "bp mario vargas llosa", "centro bp mario vargas llosa", "centro. bp mario vargas llosa", "centro. bp mario vargas llosa"],
        "lat": 40.4262,
        "lon": -3.7001,
        "district": "Centro",
        "municipality": "Madrid",
        "address": "Calle Barceló, 4, 28004 Madrid",
    },
    "ana_maria_matute": {
        "id": "ana_maria_matute",
        "name": "BP Ana María Matute (Carabanchel)",
        "aliases": ["ana maria matute", "bp ana maria matute", "carabanchel bp ana maria matute", "carabanchel. bp ana maría matute"],
        "lat": 40.3951,
        "lon": -3.7198,
        "district": "Carabanchel",
        "municipality": "Madrid",
        "address": "Calle de los Comuneros de Castilla, 30, 28019 Madrid",
    },
    "gabriel_garcia_marquez": {
        "id": "gabriel_garcia_marquez",
        "name": "BP Gabriel García Márquez (Usera)",
        "aliases": ["gabriel garcia marquez", "bp gabriel garcia marquez", "usera bp gabriel garcia marquez", "usera. bp gabriel garcía márquez"],
        "lat": 40.3756,
        "lon": -3.6972,
        "district": "Usera",
        "municipality": "Madrid",
        "address": "Plaza del Pueblo, 2, 28041 Madrid",
    },
    "huerta_de_la_salud": {
        "id": "huerta_de_la_salud",
        "name": "BP Huerta de la Salud (Hortaleza)",
        "aliases": ["huerta de la salud", "bp huerta de la salud", "hortaleza bp huerta de la salud", "hortaleza. bp huerta de la salud"],
        "lat": 40.4703,
        "lon": -3.6521,
        "district": "Hortaleza",
        "municipality": "Madrid",
        "address": "Calle Mar de las Antillas, 10, 28033 Madrid",
    },
    "hortaleza": {
        "id": "hortaleza",
        "name": "BP Hortaleza",
        "aliases": ["hortaleza", "bp hortaleza", "hortaleza bp hortaleza", "hortaleza. bp hortaleza"],
        "lat": 40.4715,
        "lon": -3.6542,
        "district": "Hortaleza",
        "municipality": "Madrid",
        "address": "Calle Arequipa, 4, 28033 Madrid",
    },
    "maria_lejarraga": {
        "id": "maria_lejarraga",
        "name": "BP María Lejárraga (Hortaleza)",
        "aliases": ["maria lejarraga", "bp maria lejarraga", "hortaleza bp maria lejarraga", "hortaleza. bp maría lejárraga"],
        "lat": 40.4795,
        "lon": -3.6475,
        "district": "Hortaleza",
        "municipality": "Madrid",
        "address": "Calle Princesa de Éboli, 29, 28050 Madrid",
    },
    "aluche": {
        "id": "aluche",
        "name": "BP Aluche (Latina)",
        "aliases": ["aluche", "bp aluche", "latina bp aluche", "latina. bp aluche"],
        "lat": 40.3879,
        "lon": -3.7547,
        "district": "Latina",
        "municipality": "Madrid",
        "address": "Calle Camarena, 10, 28047 Madrid",
    },
    "angel_gonzalez": {
        "id": "angel_gonzalez",
        "name": "BP Ángel González (Latina)",
        "aliases": ["angel gonzalez", "bp angel gonzalez", "latina bp angel gonzalez", "latina. bp ángel gonzález"],
        "lat": 40.3951,
        "lon": -3.7548,
        "district": "Latina",
        "municipality": "Madrid",
        "address": "Calle Granja del Torreón, 1, 28024 Madrid",
    },
    "canillejas": {
        "id": "canillejas",
        "name": "BP Canillejas (San Blas)",
        "aliases": ["canillejas", "bp canillejas", "san blas bp canillejas", "san blas. bp canillejas", "san blas-canillejas"],
        "lat": 40.4431,
        "lon": -3.6125,
        "district": "San Blas-Canillejas",
        "municipality": "Madrid",
        "address": "Calle Boltaña, 23, 28022 Madrid",
    },
    "san_blas": {
        "id": "san_blas",
        "name": "BP San Blas",
        "aliases": ["san blas", "bp san blas", "san blas bp san blas", "san blas. bp san blas"],
        "lat": 40.4285,
        "lon": -3.6182,
        "district": "San Blas-Canillejas",
        "municipality": "Madrid",
        "address": "Calle Pobladura del Valle, 13, 28037 Madrid",
    },
    "antonio_machado": {
        "id": "antonio_machado",
        "name": "BP Antonio Machado (Ciudad Lineal)",
        "aliases": ["antonio machado", "bp antonio machado", "ciudad lineal bp antonio machado", "ciudad lineal. bp antonio machado"],
        "lat": 40.4312,
        "lon": -3.6481,
        "district": "Ciudad Lineal",
        "municipality": "Madrid",
        "address": "Calle Santa Genoveva, 38, 28017 Madrid",
    },
    "ciudad_lineal": {
        "id": "ciudad_lineal",
        "name": "BP Ciudad Lineal",
        "aliases": ["ciudad lineal", "bp ciudad lineal", "ciudad lineal bp ciudad lineal", "ciudad lineal. bp ciudad lineal"],
        "lat": 40.4475,
        "lon": -3.6515,
        "district": "Ciudad Lineal",
        "municipality": "Madrid",
        "address": "Calle Hermanos García Noblejas, 14, 28037 Madrid",
    },
    "pablo_neruda": {
        "id": "pablo_neruda",
        "name": "BP Pablo Neruda (Ciudad Lineal)",
        "aliases": ["pablo neruda", "bp pablo neruda", "ciudad lineal bp pablo neruda", "ciudad lineal. bp pablo neruda"],
        "lat": 40.4295,
        "lon": -3.6385,
        "district": "Ciudad Lineal",
        "municipality": "Madrid",
        "address": "Calle Ascao, 4, 28017 Madrid",
    },
    "la_elipa": {
        "id": "la_elipa",
        "name": "BP La Elipa (Ciudad Lineal)",
        "aliases": ["la elipa", "bp la elipa", "ciudad lineal bp la elipa", "ciudad lineal. bp la elipa"],
        "lat": 40.4258,
        "lon": -3.6558,
        "district": "Ciudad Lineal",
        "municipality": "Madrid",
        "address": "Calle de Nuestra Señora del Villar, 6, 28017 Madrid",
    },
    "gloria_fuertes": {
        "id": "gloria_fuertes",
        "name": "BP Gloria Fuertes (Barajas)",
        "aliases": ["gloria fuertes", "bp gloria fuertes", "barajas bp gloria fuertes", "barajas. bp gloria fuertes"],
        "lat": 40.4735,
        "lon": -3.5816,
        "district": "Barajas",
        "municipality": "Madrid",
        "address": "Avenida de Logroño, 179, 28042 Madrid",
    },
    "pio_baroja": {
        "id": "pio_baroja",
        "name": "BP Pío Baroja (Arganzuela)",
        "aliases": ["pio baroja", "bp pio baroja", "arganzuela bp pio baroja", "arganzuela. bp pío baroja", "pío baroja"],
        "lat": 40.4008,
        "lon": -3.7002,
        "district": "Arganzuela",
        "municipality": "Madrid",
        "address": "Calle Arganda, 12, 28005 Madrid",
    },
    "david_gistau": {
        "id": "david_gistau",
        "name": "BP David Gistau (Salamanca)",
        "aliases": ["david gistau", "bp david gistau", "salamanca bp david gistau", "salamanca. bp david gistau"],
        "lat": 40.4325,
        "lon": -3.6738,
        "district": "Salamanca",
        "municipality": "Madrid",
        "address": "Calle Conde de Peñalver, 19, 28006 Madrid",
    },
    "maria_zambrano": {
        "id": "maria_zambrano",
        "name": "BP María Zambrano (Tetuán)",
        "aliases": ["maria zambrano", "bp maria zambrano", "tetuan bp maria zambrano", "tetuán. bp maría zambrano"],
        "lat": 40.4619,
        "lon": -3.7022,
        "district": "Tetuán",
        "municipality": "Madrid",
        "address": "Plaza de Donoso, 5, 28039 Madrid",
    },
    "manuel_vazquez_montalban": {
        "id": "manuel_vazquez_montalban",
        "name": "BP Manuel Vázquez Montalbán (Tetuán)",
        "aliases": ["manuel vazquez montalban", "bp manuel vazquez montalban", "tetuan bp manuel vazquez montalban", "tetuán. bp manuel vázquez montalbán"],
        "lat": 40.4556,
        "lon": -3.6998,
        "district": "Tetuán",
        "municipality": "Madrid",
        "address": "Calle Francos Rodríguez, 67, 28039 Madrid",
    },
    "san_fermin": {
        "id": "san_fermin",
        "name": "BP San Fermín (Usera)",
        "aliases": ["san fermin", "bp san fermin", "usera bp san fermin", "usera. bp san fermín", "san fermín"],
        "lat": 40.3701,
        "lon": -3.6938,
        "district": "Usera",
        "municipality": "Madrid",
        "address": "Avenida de San Fermín, 10, 28041 Madrid",
    },
    "chamartin_francisco_ibanez": {
        "id": "chamartin_francisco_ibanez",
        "name": "BP Francisco Ibáñez (Chamartín)",
        "aliases": ["francisco ibanez", "francisco ibáñez", "bp francisco ibanez", "bp francisco ibáñez", "chamartin bp francisco ibanez", "chamartín. bp francisco ibáñez", "chamartin"],
        "lat": 40.4542,
        "lon": -3.6761,
        "district": "Chamartín",
        "municipality": "Madrid",
        "address": "Calle Mantuano, 51, 28002 Madrid",
    },
    "vicalvaro": {
        "id": "vicalvaro",
        "name": "BP Vicálvaro",
        "aliases": ["vicalvaro", "bp vicalvaro", "vicálvaro", "vicalvaro bp vicalvaro", "vicálvaro. bp vicálvaro"],
        "lat": 40.4042,
        "lon": -3.6068,
        "district": "Vicálvaro",
        "municipality": "Madrid",
        "address": "Calle Villardondiego, 36, 28032 Madrid",
    },
    "javier_marias": {
        "id": "javier_marias",
        "name": "BP Javier Marías (Moratalaz)",
        "aliases": ["javier marias", "bp javier marias", "moratalaz bp javier marias", "moratalaz. bp javier marías"],
        "lat": 40.4095,
        "lon": -3.6452,
        "district": "Moratalaz",
        "municipality": "Madrid",
        "address": "Calle Corregidor Diego de Valderrábano, 24, 28030 Madrid",
    },
    "miguel_delibes_moratalaz": {
        "id": "miguel_delibes_moratalaz",
        "name": "BP Miguel Delibes (Moratalaz)",
        "aliases": ["miguel delibes", "bp miguel delibes", "moratalaz bp miguel delibes", "moratalaz. bp miguel delibes"],
        "lat": 40.4055,
        "lon": -3.6482,
        "district": "Moratalaz",
        "municipality": "Madrid",
        "address": "Calle Arroyo de la Media Legua, 1, 28030 Madrid",
    },
    "benjamin_palencia": {
        "id": "benjamin_palencia",
        "name": "BP Benjamín Palencia (Villa de Vallecas)",
        "aliases": ["benjamin palencia", "bp benjamin palencia", "villa de vallecas bp benjamin palencia", "villa de vallecas. bp benjamín palencia"],
        "lat": 40.3755,
        "lon": -3.6185,
        "district": "Villa de Vallecas",
        "municipality": "Madrid",
        "address": "Calle Sierra del Torcal, 12, 28031 Madrid",
    },
    "gerardo_diego": {
        "id": "gerardo_diego",
        "name": "BP Gerardo Diego (Villa de Vallecas)",
        "aliases": ["gerardo diego", "bp gerardo diego", "villa de vallecas bp gerardo diego", "villa de vallecas. bp gerardo diego"],
        "lat": 40.3822,
        "lon": -3.6212,
        "district": "Villa de Vallecas",
        "municipality": "Madrid",
        "address": "Calle Monte de Montjuich, 7, 28031 Madrid",
    },
    "francisco_umbral_villaverde": {
        "id": "francisco_umbral_villaverde",
        "name": "BP Francisco Umbral (Villaverde)",
        "aliases": ["francisco umbral", "bp francisco umbral", "villaverde bp francisco umbral", "villaverde. bp francisco umbral"],
        "lat": 40.3425,
        "lon": -3.7085,
        "district": "Villaverde",
        "municipality": "Madrid",
        "address": "Paseo de Alberto Palacios, 2, 28021 Madrid",
    },

    # --- Bibliotecas Municipales de la Comunidad de Madrid ---
    "ortega_y_gasset": {
        "id": "ortega_y_gasset",
        "name": "Biblioteca Municipal José Ortega y Gasset",
        "aliases": ["jose ortega y gasset", "ortega y gasset", "biblioteca municipal jose ortega y gasset", "biblioteca municipal josé ortega y gasset"],
        "lat": 40.4045,
        "lon": -3.8765,
        "district": "Boadilla del Monte",
        "municipality": "Boadilla del Monte",
        "address": "Calle Isabel de Farnesio, 33, 28660 Boadilla del Monte",
    },
    "pedro_antonio_de_alarcon": {
        "id": "pedro_antonio_de_alarcon",
        "name": "Biblioteca Municipal Pedro Antonio de Alarcón",
        "aliases": ["pedro antonio de alarcon", "pedro antonio de alarcón", "biblioteca municipal pedro antonio de alarcon"],
        "lat": 40.6385,
        "lon": -4.0135,
        "district": "San Lorenzo de El Escorial",
        "municipality": "San Lorenzo de El Escorial",
        "address": "Calle Vista Bella, 5, 28280 San Lorenzo de El Escorial",
    },
    "alcala_cardenal_cisneros": {
        "id": "alcala_cardenal_cisneros",
        "name": "Biblioteca Municipal Cardenal Cisneros (Alcalá de Henares)",
        "aliases": ["cardenal cisneros", "alcala de henares", "alcalá de henares", "alcala", "b.p.m. cardenal cisneros"],
        "lat": 40.4828,
        "lon": -3.3644,
        "district": "Centro",
        "municipality": "Alcalá de Henares",
        "address": "Plaza San Julián, 1, 28801 Alcalá de Henares",
    },
    "alcobendas": {
        "id": "alcobendas",
        "name": "Mediatecas de Alcobendas",
        "aliases": ["alcobendas", "biblioteca municipal de alcobendas", "mediatecas de alcobendas", "mediateca centro de arte"],
        "lat": 40.5367,
        "lon": -3.6382,
        "district": "Centro",
        "municipality": "Alcobendas",
        "address": "Avenida de España, 17, 28100 Alcobendas",
    },
    "alcorcon": {
        "id": "alcorcon",
        "name": "Biblioteca Municipal de Alcorcón",
        "aliases": ["alcorcon", "alcorcón", "biblioteca municipal de alcorcon", "biblioteca almudena grandes"],
        "lat": 40.3478,
        "lon": -3.8291,
        "district": "Centro",
        "municipality": "Alcorcón",
        "address": "Calle los Robles, 1, 28922 Alcorcón",
    },
    "getafe": {
        "id": "getafe",
        "name": "Biblioteca Municipal Ricardo de la Vega (Getafe)",
        "aliases": ["getafe", "ricardo de la vega", "biblioteca municipal de getafe"],
        "lat": 40.3065,
        "lon": -3.7312,
        "district": "Centro",
        "municipality": "Getafe",
        "address": "Calle Caladas, s/n, 28901 Getafe",
    },
    "leganes": {
        "id": "leganes",
        "name": "Biblioteca Central de Leganés",
        "aliases": ["leganes", "leganés", "biblioteca central de leganes"],
        "lat": 40.3282,
        "lon": -3.7654,
        "district": "Centro",
        "municipality": "Leganés",
        "address": "Avenida Reina Sofía, 4, 28919 Leganés",
    },
    "mostoles": {
        "id": "mostoles",
        "name": "Biblioteca Central de Móstoles",
        "aliases": ["mostoles", "móstoles", "biblioteca central de mostoles", "b. móstoles central almudena grandes"],
        "lat": 40.3225,
        "lon": -3.8647,
        "district": "Centro",
        "municipality": "Móstoles",
        "address": "Calle Pintor Velázquez, 68, 28935 Móstoles",
    },
    "pozuelo_cervantes": {
        "id": "pozuelo_cervantes",
        "name": "Biblioteca Municipal Miguel de Cervantes (Pozuelo)",
        "aliases": ["pozuelo", "pozuelo de alarcon", "pozuelo de alarcón", "biblioteca municipal miguel de cervantes"],
        "lat": 40.4412,
        "lon": -3.8152,
        "district": "Centro",
        "municipality": "Pozuelo de Alarcón",
        "address": "Plaza Mayor, 1, 28223 Pozuelo de Alarcón",
    },
    "majadahonda_umbral": {
        "id": "majadahonda_umbral",
        "name": "Biblioteca Municipal Francisco Umbral (Majadahonda)",
        "aliases": ["majadahonda", "biblioteca municipal francisco umbral majadahonda"],
        "lat": 40.4725,
        "lon": -3.8715,
        "district": "Centro",
        "municipality": "Majadahonda",
        "address": "Calle Las Norias, 39, 28220 Majadahonda",
    },
    "las_rozas_tolstoi": {
        "id": "las_rozas_tolstoi",
        "name": "Biblioteca Municipal León Tolstói (Las Rozas)",
        "aliases": ["las rozas", "leon tolstoi", "león tolstói", "biblioteca municipal leon tolstoi"],
        "lat": 40.4935,
        "lon": -3.8745,
        "district": "Centro",
        "municipality": "Las Rozas de Madrid",
        "address": "Calle Octavio Paz, 2, 28232 Las Rozas de Madrid",
    },
    "rivas_gloria_fuertes": {
        "id": "rivas_gloria_fuertes",
        "name": "Biblioteca Municipal Gloria Fuertes (Rivas)",
        "aliases": ["rivas", "rivas vaciamadrid", "rivas-vaciamadrid", "b.m. gloria fuertes"],
        "lat": 40.3542,
        "lon": -3.5385,
        "district": "Centro",
        "municipality": "Rivas-Vaciamadrid",
        "address": "Calle Jovellanos, 30, 28522 Rivas-Vaciamadrid",
    },
}


def normalize_text(text: str) -> str:
    """Normalizes string for robust matching: removes accents, punctuation, lowercases."""
    if not text:
        return ""
    # Strip accents
    nfkd_form = unicodedata.normalize('NFKD', text)
    only_ascii = "".join([c for c in nfkd_form if not unicodedata.combining(c)])
    # Lowercase and clean special chars
    cleaned = re.sub(r"[^a-zA-Z0-9\s]", " ", only_ascii).lower()
    return " ".join(cleaned.split())


def find_library_geo(raw_name: str) -> Optional[dict]:
    """Finds geographic metadata for a library name extracted from AbsysNet."""
    if not raw_name:
        return None

    norm = normalize_text(raw_name)

    # 1. Exact alias match
    for lib in MADRID_LIBRARIES_DB.values():
        for alias in lib["aliases"]:
            if normalize_text(alias) == norm:
                return lib

    # 2. Substring containment match
    for lib in MADRID_LIBRARIES_DB.values():
        for alias in lib["aliases"]:
            alias_norm = normalize_text(alias)
            if alias_norm in norm or norm in alias_norm:
                return lib

    # 3. Token-based overlap
    norm_tokens = set(norm.split()) - {"bp", "biblioteca", "publica", "municipal", "de", "la", "el", "los", "las", "y", "del", "en", "dña", "don"}
    best_lib = None
    max_overlap = 0

    for lib in MADRID_LIBRARIES_DB.values():
        for alias in lib["aliases"]:
            alias_tokens = set(normalize_text(alias).split()) - {"bp", "biblioteca", "publica", "municipal", "de", "la", "el", "los", "las", "y", "del", "en", "dña", "don"}
            overlap = len(norm_tokens & alias_tokens)
            if overlap > max_overlap and overlap >= 2:
                max_overlap = overlap
                best_lib = lib

    return best_lib


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculates the great-circle distance between two points on the Earth in kilometers."""
    R = 6371.0  # Earth's mean radius in km

    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (
        math.sin(delta_phi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2
    )
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))

    return round(R * c, 2)


def get_all_libraries_list() -> List[dict]:
    """Returns a sorted list of all known Madrid libraries for frontend selectors."""
    libs = []
    for lib in MADRID_LIBRARIES_DB.values():
        libs.append({
            "id": lib["id"],
            "name": lib["name"],
            "district": lib["district"],
            "municipality": lib["municipality"],
            "address": lib["address"],
            "lat": lib["lat"],
            "lon": lib["lon"],
        })
    return sorted(libs, key=lambda x: (x["municipality"], x["district"], x["name"]))
