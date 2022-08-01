function w = initialiseDampedNewton2d(bx,Z,a_target,per_x,per_y,areaThreshold)

% Function to find a set of weights w that together with seeds Z generates
% a c-Laguerre tessellation of bx with no empty cells, where c is the
% quadratic cost with respect to the periodic distance with periodicity in
% the x and y direction as specified by per_x and per_y. Output is only 
% defined when at least one of per_x or per_y are true.

% The weights are first defined as the c-transform of the constant zero 
% function on bx given the seeds Z. This is sufficient when the domain is
% periodic in both directions. However, if precisely one of per_x and per_y
% is true then, while the cells generated by (Z,w) are guaranteed to be 
% non-empty, there are cases in which some cells may have zero area. This 
% happens when two seeds, which lie outside the source domain, are aligned 
% perpendicular to the direction of periodicity. (See Example 2 below.) In
% this case, we define a random perturbation of the coordinates of the
% seeds, Zpert. We then solve for the optimal weights wj corresponding to a
% set of perturbed seeds Zj. This is done using the damped Newton method
% with initial weights defined as the c-transform of the constant zero 
% function on bx given the seeds Zj, which, importantly, are not aligned
% perpendicular to the direction of periodicity due to the random
% perturbation. Next we make first order approximation w to optimal weights 
% for the seeds Z using derivatives of mass map at (Zj,wj). We then check
% to see if any cell generated by (Zj,wj) has area less than the area
% threshold. If so, we decrease the amplitude of the perturbation and
% iterate. We iteratively decrease the amplitude of the perturbation until
% we obtain weights that generate no cells with area below the given
% threshold.

% Input
%{
n:= number of seeds

Format: variable - class; size; description.

    bx    - double; 1 x 4; source domain specified as [xmin,ymin,xmax,ymax]
    Z     - double; n x 2; seed locations
    per_x - logical (either true or false); 1 x 1; specifies periodicity in the x direction
    per_y - logical (either true or false); 1 x 1; specifies periodicity in the y direction

%}
% Output
%{
    w     - double; n x 1; weight vector
%}
% Example 1: iterative perturbations not needed
%{
    bx = [0,0,1,1]; % define source domain
    n  = 2000;      % number of seeds
    s  = 20;        % scale factor for seed locations
    Z  = [1,s].*rand(n,2)-[1,s/2]; % seed locations (centred around the origin)
    
    per_x = true;       
    per_y = false;
    
    w = getDefaultWeightGuess(bx,Z,per_x,per_y);
    
    a = mexPD_2d(bx,Z,w,per_x,per_y); % area of Laguerre cells in bx generated by (Z,w)
    min_a = min(a); % minimum area of any Laguerre cell in bx generated by (Z,w)

    if min_a<1e-16
        disp('Zero cell encountered.')
    else
        disp('All cells generated have positive area.')
    end
%}
% Example 2: iterative perturbations needed because the default weight
% guess generates non-empty but zero area cells returned due to seed 
% locations as described above.
%{
    bx = [0,0,1,1];
    Z = [.5,1.5;.5,2]; % seeds lie outside the source domain and are aligned perpendicular to the direction of periodicity

    per_x = true;
    per_y = false;

    w = getDefaultWeightGuess(bx,Z,per_x,per_y);

    a = mexPD_2d(bx,Z,w,per_x,per_y);
    min_a = min(a);

    if min_a==0
        disp('Zero cell encountered.')
    else
        disp('All cells generated have positive area.')
    end
%}

    % Set w to be the c-transform of the constant zero function
    w = getDefaultWeightGuess(bx,Z,per_x,per_y);
    
    % Caculate the areas of the cells generated by (Z,w). If they are all
    % above the given threshold then return w, otherwise use a seed
    % perturbation method to improve the guess for the weights.
    a = mexPDall_2d(bx,Z,w,per_x,per_y);        % areas of cells generated by Z0 and w0
    
    switch nargin
        case 4
            % If it is not already specified, define the minimum desired cell area
            % NB: This is used to avoid initialising the damped Newton algorithm with a weight vector that generates very small cells
            % NB: (bx(3)-bx(1))*(bx(4)-bx(2))/n is the average target cell
            % area, where n is the number of seeds.
            n = size(w,1);
            areaThreshold  = (1e-14)*(bx(3)-bx(1))*(bx(4)-bx(2))/n;
    end
    
    if min(a) <= areaThreshold
        % Define a fixed random perturbation to add to the seed coordinates
        n     = size(w,1);
        j     = 6;
        ZPert = (1/2^j)*((bx(3)-bx(1))*[rand(n,1),zeros(n,1)]-[ones(n,1),zeros(n,1)]*(bx(3)-bx(1))/2); % scale and translate the perturbation according to the domain
        
        % Peturb seeds
        ZNew = Z + ZPert;      % randomly perturb the seeds so that the default weight guess for damped Newton works

        % Get optimal weight vector for perturbed seeds Zj
        wNew = getDefaultWeightGuess(bx,ZNew,per_x,per_y);   % find weight guess that is sufficient to generate no zero-area cells
        wNew = dampedNewton2d(bx,ZNew,a_target,wNew,0.1,per_x,per_y); % find optimal weights for perturbed seeds
        
        %%%% Try to obtain good initial guess for seeds Z

        % Make first order approximation to optimal weights for seeds
        % Z using derivatives of mass map at (ZNew,wNew). 
        % NB: weight vector output from dampedNewton2d has final entry 0
        [~,DmDw,DmDz1,DmDz2] = getDm2d(bx,ZNew,wNew,per_x,per_y);
        DmDzTimesZInc        = -(DmDz1*ZPert(:,1) + DmDz2*ZPert(:,2)); % Note that (Z - ZNew) = -ZPert
        DmDwMod              = DmDw(1:n-1,1:n-1); 

        wInc          = zeros(n,1);
        wInc(1:end-1) = -DmDwMod\DmDzTimesZInc(1:end-1);

        w = wNew + wInc;

        % Calculate areas of cells generated by unperturbed seeds Z
        % and weights w. If one of these fals below the area threshold
        % then try with a smaller perturbation.
        a = mexPDall_2d(bx,Z,w,per_x,per_y);

        while min(a) <= areaThreshold
            ZOld = ZNew;
            wOld = wNew;
            
            % Peturb seeds with iteratively smaller perturbations
            ZPert =  ZPert/2;
            ZNew = Z + ZPert;        

            %%%% Get optimal weight vector wNew for ZNew
            
            % Generate a good guess: make first order approximation to optimal weights for seeds
            % ZNew using derivatives of mass map at (ZOld,wOld). 
            % NB: weight vector output from dampedNewton2d has final entry 0
            [~,DmDw,DmDz1,DmDz2] = getDm2d(bx,ZOld,wOld,per_x,per_y);
            DmDzTimesZInc        = -(DmDz1*ZPert(:,1) + DmDz2*ZPert(:,2)); % Note that (ZNew - ZOld) = -ZPert
            DmDwMod              = DmDw(1:n-1,1:n-1);

            wInc          = zeros(n,1);
            wInc(1:end-1) = -DmDwMod\DmDzTimesZInc(1:end-1);

            wNew = wOld + wInc;
            
            % Check whether the first order approximation, wNew, generates any zero-area cells. If so, use
            % the defualt weight guess
            aNew = mexPDall_2d(bx,ZNew,wNew,per_x,per_y);
            if min(aNew)<=areaThreshold
                wNew = getDefaultWeightGuess(bx,ZNew,per_x,per_y);   % find weight guess that is sufficient to generate no zero-area cells
            end
            wNew = dampedNewton2d(bx,ZNew,a_target,wNew,0.1,per_x,per_y);
            
            %%%% Try to obtain good initial guess for seeds Z by first
            %%%% order approximation using wNew

            % Make first order approximation to optimal weights for seeds
            % Z using derivatives of mass map at (ZNew,wNew). 
            % NB: weight vector output from dampedNewton2d has final entry 0
            [~,DmDw,DmDz1,DmDz2] = getDm2d(bx,ZNew,wNew,per_x,per_y);
            DmDzTimesZInc        = -(DmDz1*ZPert(:,1) + DmDz2*ZPert(:,2)); % Note that (Z - ZNew) = -ZPert
            DmDwMod              = DmDw(1:n-1,1:n-1); 

            wInc          = zeros(n,1);
            wInc(1:end-1) = -DmDwMod\DmDzTimesZInc(1:end-1);

            w = wNew + wInc;

            % Calculate areas of cells generated by unperturbed seeds Z
            % and weights w. If one of these fals below the area threshold
            % then try with a smaller perturbation.
            a = mexPDall_2d(bx,Z,w,per_x,per_y);
        end
        
    end
    
end