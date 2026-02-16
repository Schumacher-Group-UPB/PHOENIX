# Dispersion visualization via linear response theory 
[![arXiv][(https://img.shields.io/badge/arXiv-2507.07099-b31b1b.svg)]([https://arxiv.org/pdf/2507.07099]
This section demonstrates how PHOENIX can be used to calculate the linear response of microresonator systems. The example shows how exceptional rings emerge in spin-orbit coupled planar microresonators exhibiting circular dichroism.


We simulate the complex spatio-temporal dynamics of the respective cavity fields in time-dependent, two-dimensional real-space calculations using the following equation:

$$
i \hbar\partial_t\psi_\pm= \biggl(-\frac{\hbar^2}{2m_\mathrm{eff}}\nabla^2 + i\Gamma_\pm \biggr) \psi_\pm +J_\pm \psi_∓ +R_\pm ,
$$

The two spinor field-components are denoted by $\pm$. Here $m_\mathrm{eff}= 10^{-4}m_\mathrm{e}$ defines the effective particle mass and $\Gamma_\pm = (0.4;0.2) \mathrm{meV}$ the linewidths resulting from circular dichroism. The TE-TM splitting operator is modeled by the operator $J_\pm= \Delta_\mathrm{LT}(\partial_x ∓ i\partial_y)^2$ and the TE-TM splitting strength is defined by $\Delta_\mathrm{LT}=0.1~\mathrm{meV\upmu m^2}$. The weak Gaussian probe $R_\pm$ extracts the linear response.

<img width="3693" height="2040" alt="figure2_update" src="https://github.com/user-attachments/assets/16f8dcb4-3464-4594-b4e6-472d0e688678" />

The figure displays $-\Im(\chi)$ for the diagonal elements (a) $\chi_{++} =  \frac{\mathrm{FFT}(\psi_+)}{\mathrm{FFT}(R_+)}$ and (b) $\chi_{--} =  \frac{\mathrm{FFT}(\psi_-)}{\mathrm{FFT}(R_-)}$ (surfaces), which dominate the system response for small TE-TM splitting. For comparison the eigenvalues (dots) of the effective 2x2 Hamiltonian showing perfect agreement.
