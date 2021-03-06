% Script to define generic default parameters

% Parameters are all stored in a global structure called Par.
% Default values are set by this script. 

global Par;

Par.rand_seed = 1;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Scenario Flags                                                      %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Par.FLAG_AlgType = 1;                           % 0 = MCMC, 1 = SISR, 2 = PDAF
Par.FLAG_DynMod = 1;                            % 0 = linear Gaussian
                                                % 1 = intrinsics
Par.FLAG_ObsMod = 1;                            % 0 = linear Gaussian
                                                % 1 = bearing and range

Par.FLAG_SetInitStates = false;                 % false = generate starting points randomly. true = take starting points from Par.InitStates
Par.FLAG_KnownInitStates = true;                % true = initial target states known.
Par.FLAG_TargetsBorn = false;
Par.FLAG_TargetsDie = false;
Par.FLAG_TargetsManoeuvre = false;              % if true then accelerations must be generated
Par.FLAG_RB = false;                             % Use Rao-Blackwellisation

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Scenario Parameters                                                 %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Par.NumTgts = 1;                                % Number of targets

Par.T = 50;                                     % Number of frames
Par.P = 1; P = Par.P;                           % Sampling period
Par.Xmax = 500;                                 % Max range (half side or radius depending on observation model)
Par.Vmax = 10;                                  % Maximum velocity

Par.UnifVelDens = 1/(2*Par.Vmax)^2;             % Uniform density on velocity

Par.InitStates = {};                            % Cell array of target starting states. Size Par.NumTgts or empty

if Par.FLAG_ObsMod == 0
    Par.UnifPosDens = 1/(2*Par.Xmax)^2;         % Uniform density on position
    Par.ClutDens = Par.UnifPosDens;             % Clutter density in observation space
elseif Par.FLAG_ObsMod == 1
    Par.UnifPosDens = 1/(pi*Par.Xmax^2);        % Uniform density on position
    Par.ClutDens = (1/Par.Xmax)*(1/(2*pi));     % Clutter density in observation space
end
Par.MaxInitStateDist = 0.35;                 % Farthest a target may be initialised to the origin
Par.MinInitStateRadius = 0.25;              % Nearest a target may be initialised to the origin
Par.MaxInitStateRadius = 0.35;              % Farthest a target may be initialised to the origin

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Target dynamic model parameters                                     %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if Par.FLAG_DynMod == 0
    Par.ProcNoiseVar = 1;                                                      % Gaussian process noise variance (random accelerations)
    Par.A = [1 0 P 0; 0 1 0 P; 0 0 1 0; 0 0 0 1];                              % 2D transition matrix using near CVM model
    Par.B = [P^2/2*eye(2); P*eye(2)];                                          % 2D input transition matrix (used in track generation when we impose a deterministic acceleration)
    Par.Q = Par.ProcNoiseVar * ...
        [P^3/3 0 P^2/2 0; 0 P^3/3 0 P^2/2; P^2/2 0 P 0; 0 P^2/2 0 P];          % Gaussian motion covariance matrix (discretised continous random model)
    Par.Qchol = chol(Par.Q);                                                   % Cholesky decompostion of Par.Q
elseif Par.FLAG_DynMod == 1
    Par.B = zeros(4,2);
    Par.TangentNoiseVar = 0.1;
    Par.NormalNoiseVar = 1;
    Par.x1NoiseVar = 1;
    Par.x2NoiseVar = 1;
    Par.Q_pre = [Par.TangentNoiseVar 0 0 0;
                 0 Par.NormalNoiseVar 0 0;
                 0 0 Par.x1NoiseVar 0;
                 0 0 0 Par.x2NoiseVar];                                    % Noise variance matrix of accelerations. Must be weighted by noise jacobian before use as Q.
	Par.Q = Par.Q_pre;
    Par.Qchol = chol(Par.Q_pre)';
    Par.UQchol = chol(3*Par.Q_pre)';
    Par.MinSpeed = 0.1;
end
Par.ExpBirth = 0.1;                                                        % Expected number of new targets in a frame (poisson deistributed)
Par.PDeath = 0.01;                                                          % Probability of a (given) target death in a frame
if ~Par.FLAG_TargetsDie, Par.PDeath = 0; end
if ~Par.FLAG_TargetsBorn, Par.ExpBirth = 0; end



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Observation model parameters                                        %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Par.ExpClutObs = 1000;                      % Number of clutter objects expected in scene - 1000 is dense for Xmax=500, 160 for Xmax=200
Par.PDetect = 0.75;                         % Probability of detecting a target in a given frame

if Par.FLAG_ObsMod == 0
    Par.ObsNoiseVar = 1;                    % Observation noise variance
    Par.R = Par.ObsNoiseVar * eye(2);       % Observation covariance matrix
    Par.C = [1 0 0 0; 0 1 0 0];             % 2D Observation matrix
elseif Par.FLAG_ObsMod == 1
    Par.BearingNoiseVar = 1E-4;                                 % Bearing noise variance
    Par.RangeNoiseVar = 1;                                      % Range noise variance
    Par.R = [Par.BearingNoiseVar 0; 0 Par.RangeNoiseVar];       % Observation covariance matrix
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Algorithm parameters                                                %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Par.AnalysisLag = 5;

Par.L = 5;                              % Length of rolling window
Par.Vlimit = 1.5*Par.Vmax;              % Limit above which we do not accept velocity (lh=0)
Par.KFInitVar = 1E-20;                  % Variance with which to initialise Kalman Filters (scaled identity matrix)
Par.GateSDs = 5;                        % Number of standard deviations from the mean to the gate boundary

%%% For SISR schemes %%%
Par.NumPart = 500;                      % Number of particles per target
Par.ResamThresh = 0.1;                  % Resampling threshold as ESS/NumPart
Par.ResampleLowWeightThresh = 30;       % Orders of magnitude below max for particle killing

%%% For MCMC shemes %%%
Par.NumIt = 500;                        % Number of iterations
Par.S = 1;                              % Max distance previously from which particles are sampled
Par.BridgeLength = 1;                   % Length of bridge for bridging-history proposals.
Par.Restart = 10000;                    % Restart after this many iterations
Par.BurnIn = floor(0.1*Par.NumIt);      % Length of burn-in

%%% For MCMC-IS %%%
Par.HistoryAcceptScaling = 1;
Par.CurrentAcceptScaling = 0.5;