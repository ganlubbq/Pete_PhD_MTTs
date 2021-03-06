function [ Results ] = Track_SISR( detections, Observs, InitState )
%TRACK_SISR Track targets using SISR-PF

global Par;
global Templates;

% Initialise arrays for results, intermediates and diagnostics
Results = cell(Par.T, 1);
PartSets = cell(Par.T, 1);
BestEsts = cell(Par.T, 1);

if ~Par.FLAG_KnownInitStates
    % No knowledge of target starting positions
    InitEst = Templates.TrackSet;
    
else
    % Start with initial particle locations
    InitEst = Templates.TrackSet;
    InitEst.origin = ones(1, Par.NumTgts);
    InitEst.origin_time = ones(1, Par.NumTgts);
    for j = 1:Par.NumTgts
        if ~isempty(InitState{j})
            % Create a new track
            track = Templates.Track;
            track.birth = 0; track.death = 1; track.num = 1;
            track.state{1} = InitState{j};
            track.smooth{1} = InitState{j};
            track.covar{1} = Par.KFInitVar*eye(4);
            track.assoc = 0;
            
            % Add it to the set
            InitEst.tracks = [InitEst.tracks; track];
            InitEst.N = InitEst.N + 1;
            InitEst.members = [InitEst.members; j];
        end
    end
end

InitPartSet = struct( 'particles', [], 'weights', []);
InitPartSet.weights = repmat({log(ones(Par.NumPart,1)/Par.NumPart)}, Par.NumTgts, 1);
InitPartSet.particles = repmat({InitEst}, Par.NumPart, 1);
InitPartSet.posteriors = zeros(Par.NumPart, Par.NumTgts);

% Loop through time
for t = 1:Par.T
    
    tic;
    
    disp('**************************************************************');
    disp(['*** Now processing frame ' num2str(t)]);
    
    if t==1
        [PartSets{t}, BestEsts{t}] = SISRFrame(t, t, InitPartSet, Observs);
    else
        [PartSets{t}, BestEsts{t}] = SISRFrame(t, min(t,Par.L), PartSets{t-1}, Observs);
    end
    
    Results{t} = PartSets{t};
    
    disp(['*** Correct associations at frame ' num2str(t-min(t,Par.L)+1) ': ' num2str(detections(t-min(t,Par.L)+1,:))]);
    assoc = [];
    for j = 1:Par.NumTgts
        get_ass = cellfun(@(x) x.tracks(j).assoc(t-min(t,Par.L)+1 -x.tracks(j).birth+1), PartSets{t}.particles);
        mode_ass = mode(get_ass);
        assoc = [assoc, mode_ass];
    end
    disp(['*** Modal associations at frame ' num2str(t-min(t,Par.L)+1) ': ' num2str(assoc)]);
    
    disp(['*** Frame ' num2str(t) ' processed in ' num2str(toc) ' seconds']);
    disp('**************************************************************');
    
end

for t = 1:Par.T
    for j = 1:Par.NumTgts
        [Results{t}] = SystematicResample(j, PartSets{t}, PartSets{t}.weights{j});
    end
end

end



function [PartSet, BestEst] = SISRFrame(t, L, PrevPartSet, Observs)
% Execute a frame of the fixed-lag SISR-PF target tracker

% t - latest time frame
% L - window size
% PrevPartSet - Particle distribution from the t-1 processing step
% Observs - observations

global Par;

% Porbability arrays
post_arr = zeros(Par.NumPart,1);
reverse_kernel_arr = zeros(Par.NumPart,1);
origin_post_arr = zeros(Par.NumPart,1);
ppsl_arr = zeros(Par.NumPart,1);

% Create arrays to store diagnostics
ESS_post = zeros(Par.NumTgts,1);
ESS_pre = zeros(Par.NumTgts,1);

% Initialise particle array and weight array
PartSet = PrevPartSet;
weights = repmat({zeros(Par.NumPart,1)}, Par.NumTgts, 1);

% Project tracks forward
for ii = 1:Par.NumPart
    for j = 1:Par.NumTgts
        if t == PartSet.particles{ii}.tracks(j).death
            PartSet.particles{ii}.tracks(j) = ProjectTrack(t, PartSet.particles{ii}.tracks(j));
        end
    end
end

% Keep a copy of the projected particle set
ProjPartSet = PartSet;

% Loop through particles
for ii = 1:Par.NumPart
    
    PartStates = cell(Par.NumTgts, 1);
    PartAssocs = cell(Par.NumTgts, 1);
    PartVars = cell(Par.NumTgts, 1);
    
    % Loop through targets
    for j = 1:Par.NumTgts
        
        % Calculate reverse kernel probability
        [reverse_kernel, ~, ~] = SampleCurrent(j, t-1, L-1, PrevPartSet.particles{ii}, Observs, true);
        
        % Calculate t-1 posterior
        origin_post = SingTargPosterior(j, t-1, L-1, PrevPartSet.particles{ii}, Observs);
        
        % Propose new current states
        [ppsl, PartAssocs{j}, PartStates{j}, ~, PartVars{j}] = SampleCurrent(j, t, L, PartSet.particles{ii}, Observs, false);
        
        % Update a dummy set for calculating the posterior (we don't want
        % this target to block future ones - independence assumption)
        DummySet = ProjPartSet;
        DummySet.particles{ii}.tracks(j).state(t-L+1 -DummySet.particles{ii}.tracks(j).birth+1 : t -DummySet.particles{ii}.tracks(j).birth+1) = PartStates{j};
        DummySet.particles{ii}.tracks(j).assoc(t-L+1 -DummySet.particles{ii}.tracks(j).birth+1 : t -DummySet.particles{ii}.tracks(j).birth+1) = PartAssocs{j};
        DummySet.particles{ii}.tracks(j).covar(t-L+1 -DummySet.particles{ii}.tracks(j).birth+1 : t -DummySet.particles{ii}.tracks(j).birth+1) = PartVars{j};
        
        % Calculate t posterior
        post = SingTargPosterior(j, t, L, DummySet.particles{ii}, Observs);
        
        % Calculate weight
        weights{j}(ii) = PartSet.weights{j}(ii) ...
            + (post + reverse_kernel) ...
            - (origin_post + ppsl);
        
        if isnan(weights{j}(ii))||isinf(weights{j}(ii))
            weights{j}(ii) = -inf;
        end
        
        % Store posterior
        PartSet.posteriors(ii,j) = post;
        
        post_arr(ii) = post;
        reverse_kernel_arr(ii) = reverse_kernel;
        origin_post_arr(ii) = origin_post;
        ppsl_arr(ii) = ppsl;
        
    end
    
    % Now update the actual estimate
    for j = 1:Par.NumTgts
        PartSet.particles{ii}.tracks(j).state(t-L+1 -PartSet.particles{ii}.tracks(j).birth+1 : t -PartSet.particles{ii}.tracks(j).birth+1) = PartStates{j};
        PartSet.particles{ii}.tracks(j).assoc(t-L+1 -PartSet.particles{ii}.tracks(j).birth+1 : t -PartSet.particles{ii}.tracks(j).birth+1) = PartAssocs{j};
        PartSet.particles{ii}.tracks(j).covar(t-L+1 -PartSet.particles{ii}.tracks(j).birth+1 : t -PartSet.particles{ii}.tracks(j).birth+1) = PartVars{j};
                
        % If RB, smooth state
        if Par.FLAG_RB
            last = min(t, PartSet.particles{ii}.tracks(j).death - 1);
            first = max(1, PartSet.particles{ii}.tracks(j).birth+1);
            num = last - first + 1;
            Obs = ListAssocObservs(last, num, PartSet.particles{ii}.tracks(j), Observs);
            init_state = PartSet.particles{ii}.tracks(j).state{1 -PartSet.particles{ii}.tracks(j).birth+1};
            init_var = Par.KFInitVar*eye(4);
            [Mean, ~] = KalmanSmoother(Obs, init_state, init_var);
            PartSet.particles{ii}.tracks(j).smooth(first -PartSet.particles{ii}.tracks(j).birth+1:last -PartSet.particles{ii}.tracks(j).birth+1) = Mean;
        end 
        
    end
    
end

% Loop through targets, normalise and resample
for j = 1:Par.NumTgts
    
%     assert(~all(isinf(weights{j})), 'All weights are zero');
    
    if all(isinf(weights{j}))
        weights{j} = log(ones(Par.NumPart, 1));
    end

    % Normalise weights
    max_weight = max(weights{j}, [], 1); weights{j} = weights{j} - max_weight;
    temp = exp(weights{j}); temp = temp/sum(temp);  weights{j} = log(temp);
    
    % Attach weights to particles
    PartSet.weights{j} = weights{j};
    
    % Calculate effective sample size for diagnostics
    ESS_pre(j) = CalcESS(weights{j});
%     assert(~isnan(ESS_pre(j)), 'Effective Sample Size is non defined (probably all weights negligible)');
    if isnan(ESS_pre(j))
        weights{j} = log(ones(Par.NumPart, 1));
        ESS_pre(j) = CalcESS(weights{j});
    end
    
    if (ESS_pre(j) < Par.ResamThresh*Par.NumPart)
%         [PartSet] = ConservativeResample(j, PartSet, weights{j});
        [PartSet] = SystematicResample(j, PartSet, weights{j});
        ESS_post(j) = CalcESS(PartSet.weights{j});
        disp(['*** Target Cluster' num2str(j) ': Effective Sample Size = ' num2str(ESS_pre(j)) '. RESAMPLED. ESS = ' num2str(ESS_post(j))]);
    else
        [PartSet] = LowWeightRemoval(j, PartSet, weights{j});
        ESS_post(j) = CalcESS(PartSet.weights{j});
        disp(['*** Target Cluster' num2str(j) ': Effective Sample Size = ' num2str(ESS_pre(j))]);
    end
    
end

% Pick the best particle
total_post = sum(PartSet.posteriors, 2);
best_ind = find(total_post==max(total_post), 1);
BestEst = PartSet.particles{best_ind};
BestEst.origin(:) = best_ind;
BestEst.origin_time(:) = t;

end

