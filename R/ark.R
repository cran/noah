#' A pseudonym archive
#'
#' @description
#' An Ark object can create and remember pseudonyms.
#' Given the same input, it will always return the same pseudonym.
#' No pseudonym will repeat.
#'
#' @export

Ark <- R6::R6Class("Ark",
  public = list(

    #' @field log Hashtable for all used pseudonyms. Inputs (keys) are stored
    #' as hashes.
    log = NULL,

    #' @description Create new ark object.
    #' @param alliterate Logical. Should the Ark return alliterations by
    #' default?
    #' @param parts List of character vectors with name parts to be used for the
    #' pseudonyms. Defaults to adjectives and animals.
    #' @param seed Random seed for permutation of name parts. Use this to make
    #' Ark reproducible (to the extent that the random number generation is
    #' reproducible). If NULL (default), the random number generator is left
    #' alone. This is a convenience argument and equivalent to calling
    #' `set.seed()` before creating the Ark.
    #' @return A new `Ark` object.
    initialize = function(alliterate = FALSE, parts = NULL, seed = NULL) {
      private$parts <- if (is.null(parts)) {
        name_parts[c("adjectives", "animals")]
      } else {
        clean_name_parts(parts)
      }

      if (!is.null(seed)) {
        set.seed(seed)
      }

      private$max_total   <- prod(lengths(private$parts))
      private$index_perm  <- random_permutation(private$max_total)

      index_allit         <- private$find_alliterations()
      private$max_allit   <- length(index_allit)
      private$index_allit <- random_permutation(index_allit)
      private$alliterate  <- alliterate

      self$log            <- hash::hash()
    },

    #' @description Create Pseudonyms for input.
    #' @param ... One or more R objects.
    #' @param .alliterate Logical. Return only pseudonyms that are
    #' alliterations. Defaults to TRUE if the Ark was created with
    #' `Ark$new(alliterate = TRUE)`, FALSE otherwise. If FALSE, pseudonyms
    #' may still be alliterations by coincidence.
    #' @return Character vector of pseudonyms with same length as input.
    pseudonymize = function(..., .alliterate = NULL) {
      .alliterate <- .alliterate %||% private$alliterate
      assertthat::is.flag(.alliterate)

      if (length(unique(lengths(list(...)))) > 1) {
        stop("Error. All arguments to ... must have the same length.")
      }

      keys <- suppressMessages(dplyr::bind_cols(...))

      test_dblint <- purrr::map_lgl(list(...), ~ (is.double(.x) && all(.x %% 1 == 0)))
      if (all(test_dblint)) {
        message(paste(
          "Note. All of your numerical keys are integer numbers but",
          "have type double. `pseudonymize()` will treat numerically",
          "equivalent double and integer keys as different and assign them",
          "different pseudonyms. Use explicit coercion to avoid unexpected",
          "behavior."))
      }

      keys    <- purrr::pmap_chr(keys, ~ digest::digest(list(...)))
      n_keys  <- length(keys)
      is_in   <- hash::has.key(keys, self$log)
      n_new   <- sum(!is_in)

      if (n_new > 0) {
        tryCatch({
          if (.alliterate) {
            i <- private$index_allit(n_new)
            private$index_perm <- remove_remaining(private$index_perm, i)
          } else {
            i <- private$index_perm(n_new)
            private$index_allit <- remove_remaining(private$index_allit, i)
          }
        },
          error = function(e) {
            left_total <- private$max_total - self$length()
            left_allit <- private$max_allit - self$length_allit()
            stop(
              sprintf(paste(
                "Error. Not enough unused pseudonyms left in the Ark.",
                "Requested: %i, available: %i (%i pseudonyms).",
                "Try using custom name parts."),
                n_new, left_total, left_allit
              ),
              if (.alliterate == TRUE & n_new < left_total) {
                paste(
                  "\n Note: It seems like you requested more alliterations",
                  "than available, but there are enough pseudonyms left that",
                  "are not alliterations."
                )
              }
            )
          }
        )
        self$log[keys[!is_in]] <- private$index_to_pseudonym(i)
      }
      hash::values(self$log, keys, USE.NAMES = FALSE)
    },

    #' @description Pretty-print an Ark object.
    #' @param n A positive integer. The number of example pseudonyms to print.
    print = function(n = NULL) {

      subtle <- crayon::make_style("grey60")

      # summary
      used_total <- self$length()
      used_allit <- self$length_allit()
      perc_total <- (used_total / private$max_total) * 100
      perc_allit <- (used_allit / private$max_allit) * 100

      cat(
        subtle(
          sprintf(
            "# An%sArk",
            if(private$alliterate) " alliterating " else " "
          )
        ),
        subtle(
          sprintf(
            "# %i / %i pseudonyms used (%0.0f%%)",
            used_total, private$max_total, perc_total
          )
        ),
        subtle(
          sprintf(
            "# %i / %i alliterations used (%0.0f%%)\n",
            used_allit, private$max_allit, perc_allit
          )
        ),
        sep = "\n"
      )

      # entries
      if (self$length() == 0) {
        cat("The Ark is empty.")
      } else if (self$length() >= private$max_total) {
        cat("The Ark is full")
      } else {
        if (is.null(n)) {
          n <- 10
        } else {
          assertthat::assert_that(is.numeric(n))
          assertthat::assert_that(n > 0)
        }
        n_max <- length(self$log)
        i_max <- min(n, n_max)
        i <- 1:i_max
        k <- hash::keys(self$log)[1:i_max]
        v <- hash::values(self$log)[1:i_max]

        cat(sprintf(
          "%*s key %*s pseudonym\n",
          nchar(i_max), " ", 7, " "
        ))
        cat(
          subtle(
            crayon::italic(
              sprintf(
                "%*s <md5> %*s <Attribute Animal>\n",
                nchar(i_max), " ", 5, " "
              )
            )
          )
        )
        cat(sprintf(
          "%*s %.8s... %s",
          nchar(i_max), i, k, v
        ), sep = "\n")

        if (i_max < n_max) {
          cat(
            subtle(
              sprintf("# ...with %i more entries", n_max - i_max)
            )
          )
        }
      }
      invisible(self)
    },

    #' @description Number of used pseudonyms in an Ark.
    length = function() {
      length(self$log)
    },


    #' @description Number of used alliterations in an Ark.
    length_allit = function() {
      private$max_allit - get_n_remaining(private$index_allit)
    }
  ),

  private = list(

    # Words that will be combined to form pseudonyms.
    parts = NULL,

    # Maximum number of possible pseudonyms in the Ark.
    max_total = NULL,

    # Maximum number of possible alliterations in the Ark.
    max_allit = NULL,

    # Logical, generate alliterations by default?
    alliterate = NULL,

    # A random permutation of indices of alliterations
    index_allit = NULL,

    # index_perm a random permutation of the index
    index_perm = NULL,

    # Returns the pseudonym corresponding to a vector of indexes.
    # Argument index must be an integer or a vector of integers between 1 and
    # the Ark's max_total.
    index_to_pseudonym = function(index) {
      subs <- ind2subs(index, lengths(private$parts))

      purrr::pmap_chr(
        purrr::map2(private$parts, subs, ~ .x[.y]), paste
      )
    },

    # Find all pseudonyms that are alliterations and return numerical vector
    # containing their indexes.
    find_alliterations = function() {
      first_letters <- purrr::map(private$parts, ~ toupper(substr(.x, 1, 1)))

      # get subscripts of all name parts with matching first letter
      subs <- purrr::map_dfr(LETTERS, function(ltr) {
          purrr::map(first_letters, ~ which(.x == ltr)) %>%
            expand.grid()
      })

      subs2ind(subs, lengths(private$parts))
    }
  )
)


#' @export
length.Ark <- function(x) x$length()


#' Cleans name parts for use by an Ark.
#'
#' @keywords internal
clean_name_parts <- function(parts) {
  purrr::map(parts, ~
   .x %>%
   stringr::str_squish() %>%
   unique()
  )
}
