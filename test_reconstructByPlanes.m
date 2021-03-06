% %%%%%%%%%%%%%%%%%%%%%
% calibration
%
% %%%%%%%%%%%%%%%%%%%%%
%
%
% Parameter
%
%
squareSizeInMM = 25;
imageSize = [2448,2048];
projSize = [1024,1024];
boardSize = [11,8];
count = 14;
approximateWorkingVolume = [-150,150,-200,200,0,600];
%
%
% get camera corners
%
%
B = [];
for i = 0:count
    str_e = sprintf('in/Camera_Chessboard_corners_%d.txt',i);
    fid = fopen(str_e,'rt');
    C = textscan(fid, '%f%f');
    fclose(fid);
    A = cell2mat(C);
    B = cat(3,B,A);
end
cam_imagePoints = B;

%
% get projector corners
%
B = [];
for i = 0:count
    str_e = sprintf('in/Proj_Chessboard_corners_%d.txt',i);
    fid = fopen(str_e,'rt');
    C = textscan(fid, '%f%f');
    fclose(fid);
    A = cell2mat(C);
    B = cat(3,B,A);
end 
proj_imagePoints = B;
%
%
% calibrate camera
%
%
worldPoints = generateCheckerboardPoints(boardSize,squareSizeInMM);
params = estimateCameraParameters(cam_imagePoints,worldPoints);
%show reprojection error
showReprojectionErrors(params);
% show figure plot
figure;
showExtrinsics(params);
hold off

%
% Calibrate Projector, assign matrix [x y z px py]
%
worldPointswZ = [worldPoints,zeros(size(worldPoints,1),1)];
numOfCounts = count + 1;
tmp = [];
for i = 1:numOfCounts
    worldPointsInCamFrm =  worldPointswZ * params.RotationMatrices(1:3,1:3,i) + params.TranslationVectors(i,1:3);
    proj_imagePoints_per_count = proj_imagePoints(1:size(worldPoints,1),1:2,i);
    tmp = cat(3,tmp,[worldPointsInCamFrm,proj_imagePoints_per_count]);
end
xyzpxpy = tmp;

%
%
% Calibrate Projector, assign matrix to solve
%
% assume projector plane mode
% 1) const model: ax + by + cz + m1 * phi + m2 = 0
% 2) linear model: (a1* phi + a2)x + (b1*phi + b2)y + (c1*phi + c2)z +
% m1*phi + m2 = 0
%
% We already have x,y,z, phi from the previous steps
%
k1 = 1/abs(approximateWorkingVolume(2));
k2 = 1/abs(approximateWorkingVolume(4));
k3 = 1/abs(approximateWorkingVolume(6));
k4 = 1/abs(projSize(1));
k5 = 1/abs(projSize(2));
numOfPoints = size(worldPoints,1);
tmp = [];
tmp2 = [];
for i=1:numOfCounts
    for j = 1:numOfPoints
        x = xyzpxpy(j,1,i) * k1;
        y = xyzpxpy(j,2,i) * k2;
        z = xyzpxpy(j,3,i) * k3;
        px =  xyzpxpy(j,4,i) * k4;
        py = xyzpxpy(j,5,i) * k5;
        tmprow = [px*x,x,px*y,y,px*z,z, px,1]; %linear model
        %tmprow = [x, y, z, px, 1]; %const model
        tmp =  [tmp;tmprow];
        
        tmprow2 = [py*x,x,py*y,y,py*z,z, py,1]; %linear model
        %tmprow2 = [x, y, z, py, 1]; %const model
        tmp2 = [tmp2;tmprow2];
    end
end

%
%
% calibrate vertical projection planes
%
%
A = tmp;
[U,D,V] = svd(A);
sol_v = V(:,end);
ks_v = [k1,k2,k3,k4];
% residue
res_s = [];
for i = 1:size(xyzpxpy,1)
    for j = 1:size(xyzpxpy,3)
        phi = xyzpxpy(i,4,j);
        %[a,b,c,d] = test_reconstructByPlanes_plane_model_const(sol_v,ks_v,phi);
        [a,b,c,d] = test_reconstructByPlanes_plane_model_linear(sol_v,ks_v,phi);
        res = a * xyzpxpy(i,1,j) + b * xyzpxpy(i,2,j) + c * xyzpxpy(i,3,j) + d;
        rms = sqrt(a * a + b* b + c * c);
        res = abs(res)/ rms;
        res_s = [res_s,res];
    end
end
mean_res = mean(res_s);
max_res = max(res_s);
min_res = min(res_s);
figure;
histogram(res_s)
txt = sprintf('mean_res. max_res. min_res = %f, %f, %f', mean_res, max_res, min_res)

% show test plane 
figure;
showExtrinsics(params);
hold on

testinterval = 100;
samplestep = projSize(1) /testinterval;
for i = 1:samplestep
    phi = (i -1) * testinterval;
    %[a,b,c,d] = test_reconstructByPlanes_plane_model_const(sol_v,ks_v,phi);
    [a,b,c,d] = test_reconstructByPlanes_plane_model_linear(sol_v,ks_v,phi);
    [y,z]=meshgrid(approximateWorkingVolume(3):approximateWorkingVolume(4),approximateWorkingVolume(5):approximateWorkingVolume(6));
    x = -(d + b * y + c * z) / a;
    surf(x,z,y,'FaceColor','blue','edgecolor','none')
    alpha 0.1
    hold on
end

for i = 1:numOfPoints
    x = xyzpxpy(i,1,1);
    y = xyzpxpy(i,2,1);
    z = xyzpxpy(i,3,1);
    scatter3(x,z,y);
    hold on
end
hold off


%
%
% calibrate horizontal projection planes
%
%

A = tmp2;
[U,D,V] = svd(A);
sol_h= V(:,end);
ks_h = [k1,k2,k3,k5];
% residue
res_s = [];
for i = 1:size(xyzpxpy,1)
    for j = 1:size(xyzpxpy,3)
        phi = xyzpxpy(i,5,j);
        %[a,b,c,d] = test_reconstructByPlanes_plane_model_const(sol_h,ks_h,phi);
        [a,b,c,d] = test_reconstructByPlanes_plane_model_linear(sol_h,ks_h,phi);
        res = a * xyzpxpy(i,1,j) + b * xyzpxpy(i,2,j) + c * xyzpxpy(i,3,j) + d;
        rms = sqrt(a * a + b* b + c * c);
        res = abs(res)/ rms;
        res_s = [res_s,res];
    end
end
mean_res = mean(res_s);
max_res = max(res_s);
min_res = min(res_s);
figure;
histogram(res_s)
txt = sprintf('mean_res. max_res. min_res = %f, %f, %f', mean_res, max_res, min_res)

% test plane 
figure;
showExtrinsics(params);
hold on

testinterval = 100;
samplestep = projSize(2) /testinterval;
for i = 1:samplestep
    phi = (i -1) * testinterval;
    %[a,b,c,d] = test_reconstructByPlanes_plane_model_const(sol_h,ks_h,phi);
    [a,b,c,d] = test_reconstructByPlanes_plane_model_linear(sol_h,ks_h,phi);
    [x,z]=meshgrid(approximateWorkingVolume(1):approximateWorkingVolume(2),approximateWorkingVolume(5):approximateWorkingVolume(6));
    y = -(d + a * x + c * z) / b;
    surf(x,z,y,'FaceColor','blue','edgecolor','none')
    alpha 0.1
    hold on
end

for i = 1:numOfPoints
    x = xyzpxpy(i,1,1);
    y = xyzpxpy(i,2,1);
    z = xyzpxpy(i,3,1);
    scatter3(x,z,y);
    hold on
end
hold off