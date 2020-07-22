"""
	static_analysis(assembly; kwargs...)

Perform a static analysis of the system of nonlinear beams contained in
`assembly`. Return the resulting system and a flag indicating whether the
iteration procedure converged.

# Keyword Arguments
 - `prescribed_conditions=Dict{Int,PrescribedConditions{Float64}}()`: Dictionary
 	holding PrescribedConditions composite types for the points in `keys(prescribed_conditions)`
 - `distributed_loads=Dict{Int,DistributedLoads{Float64}}()`: Dictionary holding
 	DistributedLoads composite types for the beam elements in `keys(distributed_loads)`
 - `time_functions = TimeFunction{Float64}[]`: Array of time functions (of type TimeFunction)
 - `method=:newton`: Method (as defined in NLsolve) to solve nonlinear system of equations
 - `linesearch=LineSearches.BackTracking()`: Line search used to solve nonlinear system of equations
 - `ftol=1e-12`: tolerance for solving nonlinear system of equations
 - `iterations=1000`: maximum iterations for solving the nonlinear system of equations
 	Set <= 1 to perform a linear analysis.
 - `nstep=1`: Number of time steps. May be used in conjunction with `time_functions`
   to gradually increase displacements/loads.
"""
function static_analysis(assembly;
	prescribed_conditions = Dict{Int,PrescribedConditions{Float64}}(),
	distributed_loads = Dict{Int,DistributedLoads{Float64}}(),
	time_functions = TimeFunction{Float64}[],
	method = :newton,
	linesearch = BackTracking(),
	ftol = 1e-12,
	iterations = 1000,
	nstep = 1,
	)

	static = true

	system = System(assembly, keys(prescribed_conditions), static, length(time_functions))

	return static_analysis!(system, assembly;
		prescribed_conditions = prescribed_conditions,
		distributed_loads = distributed_loads,
		time_functions = time_functions,
		method = method,
		linesearch = linesearch,
		ftol = ftol,
		iterations = iterations,
		nstep = nstep)
end

"""
	static_analysis!(system, assembly; kwargs...)

Pre-allocated version of `static_analysis`.
"""
function static_analysis!(system, assembly;
	prescribed_conditions = Dict{Int,PrescribedConditions{Float64}}(),
	distributed_loads = Dict{Int,DistributedLoads{Float64}}(),
	time_functions = TimeFunction{Float64}[],
	method = :newton,
	linesearch = BackTracking(),
	ftol = 1e-12,
	iterations = 1000,
	nstep = 1,
	)

	# check to make sure system is static
	@assert system.static == true

	# unpack pre-allocated storage and pointers
	x = system.x
	F = system.r
	J = system.K
	time_function_values = system.time_function_values
	irow_pt = system.irow_pt
	irow_beam = system.irow_beam
	irow_beam1 = system.irow_beam1
	irow_beam2 = system.irow_beam2
	icol_pt = system.icol_pt
	icol_beam = system.icol_beam

	n_tf = length(time_functions)

	# force default time function to do nothing (in case it was accidentally changed)
	system.time_function_values[0] = 1

	converged = true
	for istep = 1:nstep

		# update time functions (except default time function)
		time_function_values[1:n_tf] .= getindex.(time_functions, istep)

		# solve the system of equations
		f! = (F, x) -> system_residual!(F, x, assembly, prescribed_conditions,
			distributed_loads, time_function_values, irow_pt, irow_beam, irow_beam1,
			irow_beam2, icol_pt, icol_beam)

		j! = (J, x) -> system_jacobian!(J, x, assembly, prescribed_conditions,
			distributed_loads, time_function_values, irow_pt, irow_beam, irow_beam1, irow_beam2,
			icol_pt, icol_beam)

		# if iterations <= 1
		# 	# linear analysis
		# 	x .= 0.0
		# 	f!(F, x)
		# 	j!(J, x)
		# 	x .= J\F
		# else
			# nonlinear analysis
			df = NLsolve.OnceDifferentiable(f!, j!, x, F, J)

			result = NLsolve.nlsolve(df, x,
				linsolve=(x,A,b)->ldiv!(x, lu(A), b),
				method=method,
				linesearch=linesearch,
				ftol=ftol,
				iterations=iterations)

			# update solution
			x .= result.zero

			# update convergence flag
			converged = result.f_converged
		# end
	end

	return system, converged
end

"""
	steady_state_analysis(assembly; kwargs...)

Perform a steady-state analysis for the system of nonlinear beams contained in
`assembly`.  Return the resulting system and a flag indicating whether the
iteration procedure converged.

# Keyword Arguments
 - `prescribed_conditions=Dict{Int,PrescribedConditions{Float64}}()`: Dictionary
 	holding PrescribedConditions composite types for the points in `keys(prescribed_conditions)`
 - `distributed_loads=Dict{Int,DistributedLoads{Float64}}()`: Dictionary holding
 	DistributedLoads composite types for the beam elements in `keys(distributed_loads)`
 - `time_functions = TimeFunction{Float64}[]`: Array of time functions (of type TimeFunction)
 - `origin = zeros(3)`: Global frame origin (for dynamic simulations)
 - `linear_velocity = zeros(3)`: Global frame linear velocity (for dynamic simulations)
 - `angular_velocity = zeros(3)`: Global frame angular velocity (for dynamic simulations)
 - `linear_velocity_tf = zeros(Int, 3)`: Time function for global frame linear velocity
 - `angular_velocity_tf = zeros(Int, 3)`: Time function for global frame angular velocity
 - `method=:newton`: Method (as defined in NLsolve) to solve nonlinear system of equations
 - `linesearch=LineSearches.BackTracking()`: Line search used to solve nonlinear system of equations
 - `ftol=1e-12`: tolerance for solving nonlinear system of equations
 - `iterations=1000`: maximum iterations for solving the nonlinear system of equations
 - `nstep=1`: Number of time steps. May be used in conjunction with `time_functions`
   to gradually increase displacements/loads.
"""
function steady_state_analysis(assembly;
	prescribed_conditions = Dict{Int,PrescribedConditions{Float64}}(),
	distributed_loads = Dict{Int,DistributedLoads{Float64}}(),
	time_functions = TimeFunction{Float64}[],
	origin = (@SVector zeros(3)),
	linear_velocity = (@SVector zeros(3)),
	angular_velocity = (@SVector zeros(3)),
	linear_velocity_tf = (@SVector zeros(Int, 3)),
	angular_velocity_tf = (@SVector zeros(Int, 3)),
	method = :newton,
	linesearch = BackTracking(),
	ftol = 1e-12,
	iterations = 1000,
	nstep = 1,
	)

	static = false

	system = System(assembly, keys(prescribed_conditions), static, length(time_functions))

	return steady_state_analysis!(system, assembly;
		prescribed_conditions = prescribed_conditions,
		distributed_loads = distributed_loads,
		time_functions = time_functions,
		origin = origin,
		linear_velocity = linear_velocity,
		angular_velocity = angular_velocity,
		linear_velocity_tf = linear_velocity_tf,
		angular_velocity_tf = angular_velocity_tf,
		method = method,
		linesearch = linesearch,
		ftol = ftol,
		iterations = iterations,
		nstep = nstep
		)
end

"""
	steady_state_analysis!(system, assembly; kwargs...)

Pre-allocated version of `steady_state_analysis`
"""
function steady_state_analysis!(system, assembly;
	prescribed_conditions = Dict{Int,PrescribedConditions{Float64}}(),
	distributed_loads = Dict{Int,DistributedLoads{Float64}}(),
	time_functions = TimeFunction{Float64}[],
	origin = (@SVector zeros(3)),
	linear_velocity = (@SVector zeros(3)),
	angular_velocity = (@SVector zeros(3)),
	linear_velocity_tf = (@SVector zeros(Int, 3)),
	angular_velocity_tf = (@SVector zeros(Int, 3)),
	method = :newton,
	linesearch = BackTracking(),
	ftol = 1e-12,
	iterations = 1000,
	nstep = 1,
	)

	# check to make sure the simulation is dynamic
	@assert system.static == false

	# unpack pre-allocated storage and pointers
	x = system.x
	F = system.r
	J = system.K
	time_function_values = system.time_function_values
	irow_pt = system.irow_pt
	irow_beam = system.irow_beam
	irow_beam1 = system.irow_beam1
	irow_beam2 = system.irow_beam2
	icol_pt = system.icol_pt
	icol_beam = system.icol_beam

	n_tf = length(time_functions)

	# force default time function to do nothing (in case it was accidentally changed)
	system.time_function_values[0] = 1

	# convert inputs for global frame motion to static arrays
	x0 = SVector{3}(origin)
	v0 = SVector{3}(linear_velocity)
	ω0 = SVector{3}(angular_velocity)
	v0_tf = SVector{3}(linear_velocity_tf)
	ω0_tf = SVector{3}(angular_velocity_tf)

	converged = true
	for istep = 1:nstep

		# update time functions (except default time function)
		time_function_values[1:n_tf] .= getindex.(time_functions, istep)

		# update global frame motion
		v0 = linear_velocity .* time_function_values[v0_tf]
		ω0 = angular_velocity .* time_function_values[ω0_tf]

		f! = (F, x) -> system_residual!(F, x, assembly, prescribed_conditions,
			distributed_loads, time_function_values, irow_pt, irow_beam,
			irow_beam1, irow_beam2, icol_pt, icol_beam, x0, v0, ω0)

		j! = (J, x) -> system_jacobian!(J, x, assembly, prescribed_conditions,
			distributed_loads, time_function_values, irow_pt, irow_beam,
			irow_beam1, irow_beam2, icol_pt, icol_beam, x0, v0, ω0)

		# solve the system of equations
		if iterations <= 1
			# linear analysis
			x .= 0.0
			f!(F, x)
			j!(J, x)
			x .= J\F
		else
			# nonlinear analysis
			df = NLsolve.OnceDifferentiable(f!, j!, x, F, J)

			result = NLsolve.nlsolve(df, x,
				linsolve=(x,A,b)->ldiv!(x, lu(A), b),
				method=method,
				linesearch=linesearch,
				ftol=ftol,
				iterations=iterations)

			# update the solution
			x .= result.zero

			# update the convergence flag
			convergence = result.f_converged
		end
	end

	return system, converged
end

"""
	eigenvalue_analysis(assembly; kwargs...)

Compute the eigenvalues and eigenvectors of the system of nonlinear beams
contained in `assembly` by calling ARPACK.  Return the eigenvalues, eigenvectors,
and a convergence flag indicating whether the corresponding steady-state analysis
converged.

# Keyword Arguments
 - `prescribed_conditions=Dict{Int,PrescribedConditions{Float64}}()`: Dictionary
 	holding PrescribedConditions composite types for the points in `keys(prescribed_conditions)`
 - `distributed_loads=Dict{Int,DistributedLoads{Float64}}()`: Dictionary holding
 	DistributedLoads composite types for the beam elements in `keys(distributed_loads)`
 - `time_functions = TimeFunction{Float64}[]`: Array of time functions (of type TimeFunction)
 - `origin = zeros(3)`: Global frame origin (for dynamic simulations)
 - `linear_velocity = zeros(3)`: Global frame linear velocity (for dynamic simulations)
 - `angular_velocity = zeros(3)`: Global frame angular velocity (for dynamic simulations)
 - `linear_velocity_tf = zeros(Int, 3)`: Time function for global frame linear velocity
 - `angular_velocity_tf = zeros(Int, 3)`: Time function for global frame angular velocity
 - `method = :newton`: Method (as defined in NLsolve) to solve nonlinear system of equations
 - `linesearch = LineSearches.BackTracking()`: Line search used to solve nonlinear system of equations
 - `ftol = 1e-12`: tolerance for solving nonlinear system of equations
 - `iterations = 1000`: maximum iterations for solving the nonlinear system of equations
 - `nstep = 1`: Number of time steps. May be used in conjunction with `time_functions`
   to gradually increase displacements/loads.
 - `nev = 6`: Number of eigenvalues to compute
"""
function eigenvalue_analysis(assembly;
	prescribed_conditions = Dict{Int,PrescribedConditions{Float64}}(),
	distributed_loads = Dict{Int,DistributedLoads{Float64}}(),
	time_functions = TimeFunction{Float64}[],
	origin = (@SVector zeros(3)),
	linear_velocity = (@SVector zeros(3)),
	angular_velocity = (@SVector zeros(3)),
	linear_velocity_tf = (@SVector zeros(Int, 3)),
	angular_velocity_tf = (@SVector zeros(Int, 3)),
	method = :newton,
	linesearch = BackTracking(),
	ftol = 1e-12,
	iterations = 1000,
	nstep = 1,
	nev = 6
	)

	static = false

	system = System(assembly, keys(prescribed_conditions), static, length(time_functions))

	return eigenvalue_analysis!(system, assembly;
		prescribed_conditions = prescribed_conditions,
		distributed_loads = distributed_loads,
		time_functions = time_functions,
		origin = origin,
		linear_velocity = linear_velocity,
		angular_velocity = angular_velocity,
		linear_velocity_tf = linear_velocity_tf,
		angular_velocity_tf = angular_velocity_tf,
		method = method,
		linesearch = linesearch,
		ftol = ftol,
		iterations = iterations,
		nstep = nstep,
		nev = nev
		)
end

"""
    eigenvalue_analysis!(system, assembly; kwargs...)

Pre-allocated version of `eigenvalue_analysis`.
"""
function eigenvalue_analysis!(system, assembly;
	prescribed_conditions = Dict{Int,PrescribedConditions{Float64}}(),
	distributed_loads = Dict{Int,DistributedLoads{Float64}}(),
	time_functions = TimeFunction{Float64}[],
	origin = (@SVector zeros(3)),
	linear_velocity = (@SVector zeros(3)),
	angular_velocity = (@SVector zeros(3)),
	linear_velocity_tf = (@SVector zeros(Int, 3)),
	angular_velocity_tf = (@SVector zeros(Int, 3)),
	method = :newton,
	linesearch = BackTracking(),
	ftol = 1e-12,
	iterations = 1000,
	nstep = 1,
	nev = 6,
	)

	# perform steady state analysis
    system, converged = steady_state_analysis!(system, assembly;
		prescribed_conditions = prescribed_conditions,
		distributed_loads = distributed_loads,
		time_functions = time_functions,
		origin = origin,
		linear_velocity = linear_velocity,
		angular_velocity = angular_velocity,
		linear_velocity_tf = linear_velocity_tf,
		angular_velocity_tf = angular_velocity_tf,
		method = method,
		linesearch = linesearch,
		ftol = ftol,
		iterations = iterations,
		nstep = nstep,
		)

	# unpack state vector, stiffness, and mass matrices
	x = system.x # populated during steady state solution
	K = system.K # needs to be updated
	M = system.M # still needs to be populated

	# also unpack system indices
	irow_pt = system.irow_pt
	irow_beam = system.irow_beam
	irow_beam1 = system.irow_beam1
	irow_beam2 = system.irow_beam2
	icol_pt = system.icol_pt
	icol_beam = system.icol_beam

	# unpack last time function values from steady state analysis
	time_function_values = system.time_function_values

	# get global frame time functions
	v0_tf = SVector{3}(linear_velocity_tf)
	ω0_tf = SVector{3}(angular_velocity_tf)

	# get global frame origin and motion
	x0 = SVector{3}(origin)
	v0 = linear_velocity .* time_function_values[v0_tf]
	ω0 = angular_velocity .* time_function_values[ω0_tf]

	# solve for the system stiffness matrix
	K = system_jacobian!(K, x, assembly, prescribed_conditions,
		distributed_loads, time_function_values, irow_pt, irow_beam,
		irow_beam1, irow_beam2, icol_pt, icol_beam, x0, v0, ω0)

	# solve for the system mass matrix
	M = system_mass_matrix!(M, x, assembly, irow_pt, irow_beam, irow_beam1,
		irow_beam2, icol_pt, icol_beam)

	# construct linear map
	T = eltype(system)
	nx = length(x)
	Kfact = lu(K)
	f! = (b, x) -> ldiv!(b, Kfact, M*x)
	fc! = (b, x) -> mul!(b, M', Kfact'\x)
	A = LinearMap{T}(f!, fc!, nx, nx; ismutating=true)

	# compute eigenvalues and right eigenvectors
	λ, V, _ = Arpack.eigs(A; nev=min(nx,nev), which=:LM)

	# eigenvalues are actually 1/λ, no modification necessary for eigenvectors
	λ .= 1 ./ λ

	return λ, V, converged
end

"""
	time_domain_analysis(assembly, dt; kwargs...)

Perform a time-domain analysis for the system of nonlinear beams contained in
`assembly`.  Return the final system, a post-processed solution history, and a
convergence flag indicating whether the iterations converged for each time step.

# Keyword Arguments
 - `prescribed_conditions = Dict{Int,PrescribedConditions{Float64}}()`: Dictionary
 	holding PrescribedConditions composite types for the points in `keys(prescribed_conditions)`
 - `distributed_loads = Dict{Int,DistributedLoads{Float64}}()`: Dictionary holding
 	DistributedLoads composite types for the beam elements in `keys(distributed_loads)`
 - `time_functions = TimeFunction{Float64}[]`: Array of time functions (of type TimeFunction)
 - `origin = zeros(3)`: Global frame origin (for dynamic simulations)
 - `linear_velocity = zeros(3)`: Global frame linear velocity (for dynamic simulations)
 - `angular_velocity = zeros(3)`: Global frame angular velocity (for dynamic simulations)
 - `linear_velocity_tf = zeros(Int, 3)`: Time function for global frame linear velocity
 - `angular_velocity_tf = zeros(Int, 3)`: Time function for global frame angular velocity
 - `u0=fill(zeros(3), length(assembly.elements))`: initial displacment of each beam element,
 - `theta0=fill(zeros(3), length(assembly.elements))`: initial angular displacement of each beam element,
 - `udot0=fill(zeros(3), length(assembly.elements))`: initial time derivative with respect to `u`
 - `thetadot0=fill(zeros(3), length(assembly.elements))`: initial time derivative with respect to `theta`
 - `method=:newton`: Method (as defined in NLsolve) to solve nonlinear system of equations
 - `linesearch=LineSearches.BackTracking()`: Line search used to solve nonlinear system of equations
 - `ftol=1e-12`: tolerance for solving nonlinear system of equations
 - `iterations=1000`: maximum iterations for solving the nonlinear system of equations
 - `nstep=1`: Number of time steps.
 - `save=1:nstep`: Steps at which to save the time history
"""
function time_domain_analysis(assembly, dt;
	prescribed_conditions = Dict{Int,PrescribedConditions{Float64}}(),
	distributed_loads = Dict{Int,DistributedLoads{Float64}}(),
	time_functions = TimeFunction{Float64}[],
	origin = (@SVector zeros(3)),
	linear_velocity = (@SVector zeros(3)),
	angular_velocity = (@SVector zeros(3)),
	linear_velocity_tf = (@SVector zeros(Int, 3)),
	angular_velocity_tf = (@SVector zeros(Int, 3)),
	u0 = fill((@SVector zeros(3)), length(assembly.elements)),
	theta0 = fill((@SVector zeros(3)), length(assembly.elements)),
	udot0 = fill((@SVector zeros(3)), length(assembly.elements)),
	thetadot0 = fill((@SVector zeros(3)), length(assembly.elements)),
	method = :newton,
	linesearch = BackTracking(),
	ftol = 1e-12,
	iterations = 1000,
	nstep = 1,
	save = 1:nstep
	)

	static = false

	system = System(assembly, keys(prescribed_conditions), static, length(time_functions))

	return time_domain_analysis!(system, assembly, dt;
		prescribed_conditions = prescribed_conditions,
		distributed_loads = distributed_loads,
		time_functions = time_functions,
		origin = origin,
		linear_velocity = linear_velocity,
		angular_velocity = angular_velocity,
		linear_velocity_tf = linear_velocity_tf,
		angular_velocity_tf = angular_velocity_tf,
		u0 = u0,
		theta0 = theta0,
		udot0 = udot0,
		thetadot0 = thetadot0,
		method = method,
		linesearch = linesearch,
		ftol = ftol,
		iterations = iterations,
		nstep = nstep,
		save = 1:nstep
		)
end

"""
    time_domain_analysis!(system, assembly, dt; kwargs...)

Pre-allocated version of `time_domain_analysis`.
"""
function time_domain_analysis!(system, assembly, dt;
	prescribed_conditions = Dict{Int,PrescribedConditions{Float64}}(),
	distributed_loads = Dict{Int,DistributedLoads{Float64}}(),
	time_functions = TimeFunction{Float64}[],
	origin = (@SVector zeros(3)),
	linear_velocity = (@SVector zeros(3)),
	angular_velocity = (@SVector zeros(3)),
	linear_velocity_tf = (@SVector zeros(Int, 3)),
	angular_velocity_tf = (@SVector zeros(Int, 3)),
	u0 = fill((@SVector zeros(3)), length(assembly.elements)),
	theta0 = fill((@SVector zeros(3)), length(assembly.elements)),
	udot0 = fill((@SVector zeros(3)), length(assembly.elements)),
	thetadot0 = fill((@SVector zeros(3)), length(assembly.elements)),
	method = :newton,
	linesearch = BackTracking(),
	ftol = 1e-12,
	iterations = 1000,
	nstep = 1,
	save = 1:nstep
	)

	# check to make sure the simulation is dynamic
	@assert system.static == false

	# unpack pre-allocated storage and pointers for system
	x = system.x
	F = system.r
	J = system.K
	time_function_values = system.time_function_values
	irow_pt = system.irow_pt
	irow_beam = system.irow_beam
	irow_beam1 = system.irow_beam1
	irow_beam2 = system.irow_beam2
	icol_pt = system.icol_pt
	icol_beam = system.icol_beam
	udot_init = system.udot_init
	θdot_init = system.θdot_init
	CtCabPdot_init = system.CtCabPdot_init
	CtCabHdot_init = system.CtCabHdot_init

	# extract some useful dimensions for later
	nbeam = length(assembly.elements)
	n_tf = length(time_functions)

	# force default time function to do nothing (in case it was accidentally changed)
	system.time_function_values[0] = 1

	# convert inputs for global frame motion to static arrays
	x0 = SVector{3}(origin)
	v0 = SVector{3}(linear_velocity)
	ω0 = SVector{3}(angular_velocity)
	v0_tf = SVector{3}(linear_velocity_tf)
	ω0_tf = SVector{3}(angular_velocity_tf)

	# --- Initial Condition Run --- #

	# update time functions
	time_function_values[1:n_tf] .= getindex.(time_functions, 1)

	# get global frame motion
	v0 = SVector{3}(linear_velocity) .* time_function_values[v0_tf]
	ω0 = SVector{3}(angular_velocity) .* time_function_values[ω0_tf]

	# construct residual and jacobian functions
	f! = (F, x) -> system_residual!(F, x, assembly, prescribed_conditions,
		distributed_loads, time_function_values, irow_pt, irow_beam,
		irow_beam1, irow_beam2, icol_pt, icol_beam, x0, v0, ω0, u0, theta0,
		udot0, thetadot0)

	j! = (J, x) -> system_jacobian!(J, x, assembly, prescribed_conditions,
		distributed_loads, time_function_values, irow_pt, irow_beam,
		irow_beam1, irow_beam2, icol_pt, icol_beam, x0, v0, ω0, u0, theta0,
		udot0, thetadot0)

	# solve system of equations
	if iterations <= 1
		# linear analysis
		x .= 0.0
		f!(F, x)
		j!(J, x)
		x .= J\F
	else
		# nonlinear analysis
		df = OnceDifferentiable(f!, j!, x, F, J)

		result = NLsolve.nlsolve(df, x,
			linsolve=(x,A,b)->ldiv!(x, lu(A), b),
			method=method,
			linesearch=linesearch,
			ftol=ftol,
			iterations=iterations)

		x .= result.zero
	end

	# --- End Initial Condition Run --- #

	# now set up for the time-domain run
	for ibeam = 1:nbeam
		icol = icol_beam[ibeam]
		# calculate udot_init
		udot_init[ibeam] = 2/dt*u0[ibeam] + udot0[ibeam]
		# calculate θdot_init
		θdot_init[ibeam] = 2/dt*theta0[ibeam] + thetadot0[ibeam]
		# extract rotation parameters
		C = get_C(theta0[ibeam])
		Cab = assembly.elements[ibeam].Cab
		CtCab = C'*Cab
		# calculate CtCabPdot_init
		CtCabP = CtCab*SVector{3}(x[icol+12], x[icol+13], x[icol+14])
		CtCabPdot = SVector{3}(x[icol], x[icol+1], x[icol+2])
		CtCabPdot_init[ibeam] = 2/dt*CtCabP + CtCabPdot
		# calculate CtCabHdot_init
		CtCabH = CtCab*SVector{3}(x[icol+15], x[icol+16], x[icol+17])
		CtCabHdot = SVector{3}(x[icol+3], x[icol+4], x[icol+5])
		CtCabHdot_init[ibeam] = 2/dt*CtCabH + CtCabHdot
		# insert initial conditions for time-domain analysis
		x[icol:icol+2] .= u0[ibeam]
		x[icol+3:icol+5] .= theta0[ibeam]
	end

	# initialize storage for each time step
	isave = 1
	history = Vector{AssemblyState{eltype(system)}}(undef, length(save))

	# add initial state to the solution history (if it should be saved)
	if 1 in save
		history[isave] = AssemblyState(system, assembly, prescribed_conditions = prescribed_conditions)
		isave += 1
	end

	# --- Begin Time Domain Simulation --- #

	for istep = 2:nstep
		# update time functions (except default time function)
		time_function_values[1:n_tf] .= getindex.(time_functions, istep)

		v0 = SVector{3}(linear_velocity) .* time_function_values[v0_tf]
		ω0 = SVector{3}(angular_velocity) .* time_function_values[ω0_tf]

		# solve for the state variables at the next time step
		f! = (F, x) -> system_residual!(F, x, assembly, prescribed_conditions,
			distributed_loads, time_function_values, irow_pt, irow_beam,
			irow_beam1, irow_beam2, icol_pt, icol_beam, x0, v0, ω0, udot_init,
			θdot_init, CtCabPdot_init, CtCabHdot_init, dt)

		j! = (J, x) -> system_jacobian!(J, x, assembly, prescribed_conditions,
			distributed_loads, time_function_values, irow_pt, irow_beam,
			irow_beam1, irow_beam2, icol_pt, icol_beam, x0, v0, ω0, udot_init,
			θdot_init, CtCabPdot_init, CtCabHdot_init, dt)

		# solve system of equations
		if iterations <= 1
			# linear analysis
			x .= 0.0
			f!(F, x)
			j!(J, x)
			x .= J\F
		else
			df = OnceDifferentiable(f!, j!, x, F, J)

			result = NLsolve.nlsolve(df, x,
				linsolve=(x,A,b)->ldiv!(x, lu(A), b),
				method=method,
				linesearch=linesearch,
				ftol=ftol,
				iterations=iterations)

			x .= result.zero
		end

		# add state to history
		if istep in save
			history[isave] = AssemblyState(system, assembly, prescribed_conditions = prescribed_conditions)
			isave += 1
		end

		# stop early if unconverged
		if !result.f_converged
			break
		end

		# exit loop if done iterating
		if istep == nstep
			break
		end

		# update time derivative terms for the next time step
		for ibeam = 1:nbeam
			icol = icol_beam[ibeam]
			# calculate udot for next time step
			u = SVector(x[icol], x[icol+1], x[icol+2])
			udot = 2/dt*u - udot_init[ibeam]
			udot_init[ibeam] = 2/dt*u + udot
			# calculate θdot for next time step
			θ = SVector(x[icol+3], x[icol+4], x[icol+5])
			θdot = 2/dt*θ - θdot_init[ibeam]
			θdot_init[ibeam] = 2/dt*θ + θdot
			# extract rotation parameters
			C = get_C(θ)
			Cab = assembly.elements[ibeam].Cab
			CtCab = C'*Cab
			# calculate CtCabPdot for next time step
			CtCabP = CtCab*SVector(x[icol+12], x[icol+13], x[icol+14])
			CtCabPdot = 2/dt*CtCabP - CtCabPdot_init[ibeam]
			CtCabPdot_init[ibeam] = 2/dt*CtCabP + CtCabPdot
			# calculate CtCabHdot for next time step
			CtCabH = CtCab*SVector(x[icol+15], x[icol+16], x[icol+17])
			CtCabHdot = 2/dt*CtCabH - CtCabHdot_init[ibeam]
			CtCabHdot_init[ibeam] = 2/dt*CtCabH + CtCabHdot
		end
	end

	# --- End Time Domain Simulation --- #

	return system, history, converged
end