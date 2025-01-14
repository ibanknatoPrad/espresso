!
! Copyright (C) 2001 PWSCF group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!----------------------------------------------------------------------------
! TB
! setup of the gate, search for 'TB'
!----------------------------------------------------------------------------
!
!----------------------------------------------------------------------
SUBROUTINE setlocal
  !----------------------------------------------------------------------
  !
  !    This routine computes the local potential in real space vltot(ir)
  !
  USE io_global, ONLY : stdout
  USE kinds,     ONLY : DP
  USE constants, ONLY : eps8
  USE ions_base, ONLY : zv, ntyp => nsp
  USE cell_base, ONLY : omega
  USE extfield,  ONLY : tefield, dipfield, etotefield, gate, etotgatefield !TB
  USE gvect,     ONLY : igtongl, gg
  USE scf,       ONLY : rho, v_of_0, vltot
  USE vlocal,    ONLY : strf, vloc
  USE fft_base,  ONLY : dfftp
  USE fft_interfaces,ONLY : invfft
  USE gvect,     ONLY : ngm
  USE control_flags, ONLY : gamma_only
  USE mp_bands,  ONLY : intra_bgrp_comm
  USE mp,        ONLY : mp_sum
  USE martyna_tuckerman, ONLY : wg_corr_loc, do_comp_mt
  USE esm,       ONLY : esm_local, esm_bc, do_comp_esm
  USE qmmm,      ONLY : qmmm_add_esf
  USE Coul_cut_2D, ONLY : do_cutoff_2D, cutoff_local 
  USE rism_module, ONLY : lrism, rism_setlocal
  !
  IMPLICIT NONE
  COMPLEX(DP), ALLOCATABLE :: aux (:), v_corr(:)
  COMPLEX(DP), ALLOCATABLE :: vlesm(:)
  REAL(DP),    ALLOCATABLE :: vrism(:)
  ! auxiliary variable
  INTEGER :: nt, ng
  ! counter on atom types
  ! counter on g vectors
  !
  ALLOCATE (aux( dfftp%nnr))
  aux(:)=(0.d0,0.d0)
  ALLOCATE (vlesm(dfftp%nnr))
  vlesm(:)=(0.d0,0.d0)
  !
  IF (do_comp_mt) THEN
      ALLOCATE(v_corr(ngm))
      CALL wg_corr_loc(omega,ntyp,ngm,zv,strf,v_corr)
      aux(dfftp%nl(:)) = v_corr(:)
      DEALLOCATE(v_corr)
  END IF
  !
  DO nt = 1, ntyp
      DO ng = 1, ngm
          aux (dfftp%nl(ng))=aux(dfftp%nl(ng)) + vloc (igtongl (ng), nt) * strf (ng, nt)
      END DO
  END DO
  IF (gamma_only) THEN
      DO ng = 1, ngm
          aux (dfftp%nlm(ng)) = CONJG(aux (dfftp%nl(ng)))
      END DO
  END IF
  !
  IF ( do_comp_esm .AND. ( esm_bc .NE. 'pbc' ) ) THEN
     !
     ! ... Perform ESM correction to local potential
     !
      CALL esm_local ( vlesm )
      aux = aux + vlesm
  ENDIF
  !
  ! 2D: re-add the erf/r function
  IF ( do_cutoff_2D ) THEN
     !
     ! ... re-add the CUTOFF fourier transform of erf function
     !
      CALL cutoff_local ( aux )
  ENDIF 
  !
  ! ... v_of_0 is (Vloc)(G=0)
  !
  v_of_0=0.0_DP
  IF (gg(1) < eps8) v_of_0 = DBLE ( aux (dfftp%nl(1)) )
  !
  CALL mp_sum( v_of_0, intra_bgrp_comm )
  !
  ! ... aux = potential in G-space . FFT to real space
  !
  CALL invfft ('Rho', aux, dfftp)
  !
  vltot (:) =  DBLE (aux (:) )
  !
  ! ... If required add an electric field to the local potential 
  !
  IF ( tefield .AND. ( .NOT. dipfield ) )  &
      CALL add_efield(vltot,etotefield,rho%of_r,.TRUE.)
  !
  ! TB
  ! if charged plate, call add_gatefield and add the linear potential, together with the background charge
  IF (gate) CALL add_gatefield(vltot,etotgatefield,.true.,.true.)

  !
  !  ... Add the electrostatic field generated by MM atoms
  !  in a QM/MM calculation to the local potential
  !
  CALL qmmm_add_esf(vltot,dfftp)
  !
  ! ... set the local potential to rism_module
  !
  IF (lrism) THEN
      IF ( do_comp_esm .AND. ( esm_bc .NE. 'pbc' ) ) THEN
          !
          ! ... for Laue-RISM
          !
          ALLOCATE(vrism(dfftp%nnr))
          CALL invfft ('Rho', vlesm, dfftp)
          vrism(:) = vltot(:) - DBLE(vlesm(:))
          CALL rism_setlocal(vrism)
          DEALLOCATE(vrism)
      ELSE
          !
          ! ... for 3D-RISM
          !
          CALL rism_setlocal(vltot)
      END IF
  END IF
  !
  ! ... Save vltot for possible modifications in plugins
  !
  CALL plugin_init_potential(vltot)
  !
  DEALLOCATE(aux)
  DEALLOCATE(vlesm)
  !
  RETURN
END SUBROUTINE setlocal

