! -----------------------------------------------------------------------------
! Beginning of hashtable.
! this file can be 'INCLUDE'ed verbatim in various place, where it needs to be
! part of the module to guarantee inlining
! hashes (c,p) pairs, where p is assumed to be >0
! on return (0 is used as a flag for not present)
!
!
! *****************************************************************************
!> \brief finds a prime equal or larger than i, needed at creation
!> \param i ...
!> \return ...
! **************************************************************************************************
  FUNCTION matching_prime(i) RESULT(res)
     INTEGER, INTENT(IN)                      :: i
     INTEGER                                  :: res

     INTEGER                                  :: j

     res = i
     j = 0
     DO WHILE (j < res)
        DO j = 2, res-1
           IF (MOD(res, j) == 0) THEN
              res = res+1
              EXIT
           ENDIF
        ENDDO
     ENDDO
  END FUNCTION

! *****************************************************************************
!> \brief create a hash_table of given initial size.
!>        the hash table will expand as needed (but this requires rehashing)
!> \param hash_table ...
!> \param table_size ...
! **************************************************************************************************
  SUBROUTINE hash_table_create(hash_table, table_size)
     TYPE(hash_table_type)                    :: hash_table
     INTEGER, INTENT(IN)                      :: table_size

     INTEGER                                  :: j

     ! guarantee a minimal hash table size (8), so that expansion works

     j = 3
     DO WHILE (2**j-1 < table_size)
        j = j+1
     ENDDO
     hash_table%nmax = 2**j-1
     hash_table%prime = matching_prime(hash_table%nmax)
     hash_table%nele = 0
     ALLOCATE (hash_table%table(0:hash_table%nmax))
  END SUBROUTINE hash_table_create

! *****************************************************************************
!> \brief ...
!> \param hash_table ...
! **************************************************************************************************
  SUBROUTINE hash_table_release(hash_table)
     TYPE(hash_table_type)                    :: hash_table

     hash_table%nmax = 0
     hash_table%nele = 0
     DEALLOCATE (hash_table%table)

  END SUBROUTINE hash_table_release

! *****************************************************************************
!> \brief add a pair (c,p) to the hash table
!> \param hash_table ...
!> \param c this value is being hashed
!> \param p this is being stored
! **************************************************************************************************
  RECURSIVE SUBROUTINE hash_table_add(hash_table, c, p)
     TYPE(hash_table_type), INTENT(INOUT)     :: hash_table
     INTEGER, INTENT(IN)                      :: c, p

     REAL(KIND=sp), PARAMETER :: hash_table_expand = 1.5_sp, &
                                 inv_hash_table_fill = 2.5_sp

     INTEGER                                  :: i, j
     TYPE(hash_ele_type), ALLOCATABLE, &
        DIMENSION(:)                           :: tmp_hash

! if too small, make a copy and rehash in a larger table

     IF (hash_table%nele*inv_hash_table_fill > hash_table%nmax) THEN
        ALLOCATE (tmp_hash(LBOUND(hash_table%table, 1):UBOUND(hash_table%table, 1)))
        tmp_hash(:) = hash_table%table
        CALL hash_table_release(hash_table)
        CALL hash_table_create(hash_table, INT((UBOUND(tmp_hash, 1)+8)*hash_table_expand))
        DO i = LBOUND(tmp_hash, 1), UBOUND(tmp_hash, 1)
           IF (tmp_hash(i)%c .NE. 0) THEN
              CALL hash_table_add(hash_table, tmp_hash(i)%c, tmp_hash(i)%p)
           ENDIF
        ENDDO
        DEALLOCATE (tmp_hash)
     ENDIF

     hash_table%nele = hash_table%nele+1
     i = IAND(c*hash_table%prime, hash_table%nmax)

     DO j = i, hash_table%nmax
        IF (hash_table%table(j)%c == 0 .OR. hash_table%table(j)%c == c) THEN
           hash_table%table(j)%c = c
           hash_table%table(j)%p = p
           RETURN
        ENDIF
     ENDDO
     DO j = 0, i-1
        IF (hash_table%table(j)%c == 0 .OR. hash_table%table(j)%c == c) THEN
           hash_table%table(j)%c = c
           hash_table%table(j)%p = p
           RETURN
        ENDIF
     ENDDO

  END SUBROUTINE hash_table_add

! *****************************************************************************
!> \brief ...
!> \param hash_table ...
!> \param c ...
!> \return ...
! **************************************************************************************************
  PURE FUNCTION hash_table_get(hash_table, c) RESULT(p)
     TYPE(hash_table_type), INTENT(IN)        :: hash_table
     INTEGER, INTENT(IN)                      :: c
     INTEGER                                  :: p

     INTEGER                                  :: i, j

     i = IAND(c*hash_table%prime, hash_table%nmax)

     ! catch the likely case first
     IF (hash_table%table(i)%c == c) THEN
        p = hash_table%table(i)%p
        RETURN
     ENDIF

     DO j = i, hash_table%nmax
        IF (hash_table%table(j)%c == 0 .OR. hash_table%table(j)%c == c) THEN
           p = hash_table%table(j)%p
           RETURN
        ENDIF
     ENDDO
     DO j = 0, i-1
        IF (hash_table%table(j)%c == 0 .OR. hash_table%table(j)%c == c) THEN
           p = hash_table%table(j)%p
           RETURN
        ENDIF
     ENDDO

     ! we should never reach this point.
     p = HUGE(p)

  END FUNCTION hash_table_get

! **************************************************************************************************
!> \brief Fills row hashtable from an existing matrix.
!> \param hashes ...
!> \param matrix ...
!> \param[in] block_estimate guess for the number of blocks in the product matrix, can be zero
!> \param row_map ...
!> \param col_map ...
! **************************************************************************************************
  SUBROUTINE fill_hash_tables(hashes, matrix, block_estimate, row_map, col_map)
     TYPE(hash_table_type), DIMENSION(:), INTENT(inout) :: hashes
     TYPE(dbcsr_type), INTENT(IN)                       :: matrix
     INTEGER                                            :: block_estimate
     INTEGER, DIMENSION(:), INTENT(IN)                  :: row_map, col_map

     CHARACTER(len=*), PARAMETER :: routineN = 'fill_hash_tables', &
                                    routineP = moduleN//':'//routineN

     INTEGER                                            :: col, handle, i, imat, n_rows, row

!  ---------------------------------------------------------------------------

     CALL timeset(routineN, handle)
     imat = 1
!$   imat = OMP_GET_THREAD_NUM()+1
     n_rows = matrix%nblkrows_local
     IF (SIZE(hashes) /= n_rows) &
        DBCSR_ABORT("Local row count mismatch")
     DO row = 1, n_rows
        ! create the hash table row with a reasonable initial size
        CALL hash_table_create(hashes(row), &
                               MAX(8, (3*block_estimate)/MAX(1, n_rows)))
     ENDDO
     ! We avoid using the iterator because we will use the existing
     ! work matrix instead of the BCSR index.
     DO i = 1, matrix%wms(imat)%lastblk
        row = matrix%wms(imat)%row_i(i)
        col = matrix%wms(imat)%col_i(i)
        row = row_map(row)
        col = col_map(col)
        CALL hash_table_add(hashes(row), col, i)
     ENDDO
     CALL timestop(handle)
  END SUBROUTINE fill_hash_tables

! End of hashtable
! -----------------------------------------------------------------------------