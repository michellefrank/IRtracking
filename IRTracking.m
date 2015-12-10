%% IR tracking - a most-automated way to tracking locomotion in IR videos
% Stephen Zhang 11-24-2015

%% Set parameters
% Set target fps
targetfps = 3.5;

% Set frame-gaps used for background calculation
bg_frame_gaps = 1;

% First frame to load (for tracking and background calculation)
firstframe2load = 13;

% Last frame to load (a debugging variable)
lastframe2load = nVidFrame - 13;

% Last frame used for background
bg_lastframe2load = nVidFrame - 13;

% Max tunning threshold
Max_threshold = 100;

% Channel to choose: red = 1, blue = 2, or green = 3
RGBchannel = 1;

% The size of erosion
erosionsize = 1;

% Direction 1 = fly moving horizontally  2 = vertically
flydirection = 1;

% Frames used to tune threshold2
nframesthresh2 = 3;

%% Load video
% Specify video name and path
[filename, vidpath] = uigetfile('D:\Projects\Visual-processing\*.wmv','Select the video file');
addpath(vidpath);

% Get common parameters
VidObj = VideoReader(fullfile(vidpath,filename));

nVidFrame = VidObj.NumberOfFrames;
vidHeight = VidObj.Height;
vidWidth = VidObj.Width;
vidfps = VidObj.FrameRate;
vidDuration = VidObj.Duration;

%% Crop-out the ROI
% Read out the first frame

sampleframe = read(VidObj , firstframe2load);

% Only use the Red channel
sampleframe = sampleframe(:,:,RGBchannel);

% Manually select ROI
[sampleframe_cr, cropindices] = imcrop(sampleframe);
cropindices = floor(cropindices);
close(gcf)


%% Calculate background
% Calculate the frames used for background computation
bg_frames = firstframe2load : bg_frame_gaps : bg_lastframe2load;
n_bg_frames = length(bg_frames);

% Determine the size of each frame after cropping
all_arena_size = size(sampleframe_cr);

% Create background stack
bg_stack = uint8( zeros( all_arena_size(1), all_arena_size(2), n_bg_frames ) );

% Use text progress bar
textprogressbar('Loading background: ');


% Load the background stack
for i = 1 : n_bg_frames
    % Load a tempporary frame
    im = read(VidObj , i);
    
    % Apply manual cropping
    bg_stack(:,:,i) = im(cropindices(2):cropindices(2)+cropindices(4),...
        cropindices(1):cropindices(1)+cropindices(3), RGBchannel);
    
    % Update text progress bar
    textprogressbar(i/n_bg_frames*100);
end

% Use median to apply background
background = single(median(bg_stack, 3));

% Finish text progress bar
textprogressbar('Done!');

%% Set threshold for finding wells
figure(101)
set(101,'Position',[100 50 1000 600])

% Showcase all the threshold levels
for i = 1 : 8
    subplot(2,4,i);
    imshow(im2bw(sampleframe_cr, i/10));
    text(10,15,num2str(i/10),'Color',[1 0 0]);
end

% Input the threshold
threshold = input('Threshold=');
close(101)

%% Find and sort arenas from top to bottom (or left to right)
% Apply threshold to find the arenas
[all_arenas , n_arenas] = bwlabel(im2bw(sampleframe_cr, threshold));
disp(['Found ', num2str(n_arenas), ' arenas.'])

% Use the centroids of the arenas to sort them from top to bottom
centroids = regionprops(all_arenas,'Centroid');
centroids = round(cell2mat({centroids.Centroid}'));

if flydirection == 1
    % Top to down
    centroids_y = centroids(:,2);
    [~, arena_order] = sort(centroids_y,'ascend');
else
    % Left to right
    centroids_x = centroids(:,1);
    [~, arena_order] = sort(centroids_x,'ascend');

end
% 

% Apply the sorted arena order to relabel the new arenas order (1 - top, 2 
% - second from top..., n - bottom)
all_arenas_new = all_arenas;

for i = 1 : n_arenas
    all_arenas_new(all_arenas==arena_order(i)) = i;
end

all_arenas_new = imfill(all_arenas_new);

% Find the boundries of the new arenas
% extremas = regionprops(all_arenas_new,'Extrema');

%% Loading arenas
% For reference, 15 fps for 1 hour at 640x480 is about 16 GB
% Ajudt how many frames to skip during loading
frames2skip = round(vidfps/targetfps);

% Generate a vector of which frames to load
frames2load_vec = firstframe2load : frames2skip : lastframe2load;

% Calculate how many frames to load
nframe2load = length(frames2load_vec);

% Create arena stack
arena = uint8( zeros( all_arena_size(1), all_arena_size(2), nframe2load ) );

% A stack used to detect gross movements of the arena (debug)
% arena_gross = arena;

% A erosoin mask used to remove the arena edges
erosion_mask = all_arenas > 0;
erosion_mask = uint8(imerode(erosion_mask,strel('disk',erosionsize)));

% Initialize text progress bar
textprogressbar('Loading arena stack: ');

for i = 1 : nframe2load
    % Loading
    im = single(read(VidObj , frames2load_vec(i)));

    % Apply manual cropping and background
    arena(:,:,i) = uint8(-im(cropindices(2):cropindices(2)+cropindices(4),...
    cropindices(1):cropindices(1)+cropindices(3), RGBchannel)...
    + background) .* erosion_mask;

    % Update arena gross (debug)
    % arena_gross(:,:,i) = uint8(im2bw(im(cropindices(2):cropindices(2)+cropindices(4),...
    % cropindices(1):cropindices(1)+cropindices(3), RGBchannel),threshold));

    % Update progress bar
    textprogressbar(i/nframe2load*100);
end

% Terminate text progress bar
textprogressbar('Done!');

%% Detect the gross movement of the arena (debug)

% arena_move = diff(arena_gross,1,3);

% plot(squeeze(sum(sum(test))))



%% Tune the threshold to pickout flies.
% Define the imaged used to tune threshold2
tunning_image = repmat(arena(:,:,1), [1 1 nframesthresh2]);

% Load the images, which are equally spaced apart in the entire stack
for i = 1 : nframesthresh2
    tunning_image(:,:,i) = arena(:,:,...
        round(nframe2load/(nframesthresh2 + 1) * i));
end

Tunning_vec = zeros(Max_threshold , 3 , nframesthresh2);

for j = 1 : nframesthresh2
    for i = 1 : Max_threshold
        [sorted_image, sorted_areas, n_areas_found] =...
            areasort(tunning_image (:,:,j)>i, n_arenas);
        if n_areas_found >= n_arenas
            % Calculate precision
            Tunning_vec(i,1,j) = sum(sorted_areas(1:n_arenas)) / sum(sorted_areas);

            % Calculate recall
            % If no fly is detected in any well, set recall to 0;
            sorted_image_labeled = double(sorted_image>0) .* all_arenas_new;

            if length(unique(sorted_image_labeled(:))) == n_arenas + 1
                Tunning_vec(i,2,j) = 1;
            end

            % Calculate F1 score
            Tunning_vec(i,3,j) = 2 * Tunning_vec(i,1,j) * Tunning_vec(i,2,j)...
                / (Tunning_vec(i,1,j) + Tunning_vec(i,2,j));
        end
    end
end

figure(101)
plot(squeeze(Tunning_vec(:,3,:)), 'o-','LineWidth',3)
xlabel('Threshold')
ylabel('F1 score')
legend({'Sample Frame 1', 'Sample Frame 2', 'Sample Frame 3'})

grid on

% Input the threshold
threshold2 = input('Threshold2=');
close(101)

%% Final segmentation
% Create arena stack to store the segmented arena stack
arena_final = arena;

% Prime a thresholds vector for debugging
thresholds_final = threshold2 * ones(nframe2load,1);

% Initiate textprogressbar
textprogressbar('Final segmentation: ');


for i = 1 : nframe2load
    % Apply threshold
    im2 = arena(:,:,i) > threshold2;
    
    % Test how many flies are detected
    [~, n_flies_detected] = bwlabel(im2, 4);
    
    if n_flies_detected < n_arenas
        % Prepare to decrease threshold
        threshold_tmp = threshold2;
        
        while n_flies_detected < n_arenas
            % Decrease threshold
            threshold_tmp = threshold_tmp - 1;
            
            % Applied decrease threshold
            im2 = arena(:,:,i) > threshold_tmp;
            
            % Count the number of flies detected
            [~, n_flies_detected] = bwlabel(im2, 4);
        end
        
        % Apply areasort in case extraflies were created as threshold is
        % decrased
        im2 = areasort(im2, n_arenas);
        im2 = im2 > 0;
        
        % Log threshold
        thresholds_final(i) = threshold_tmp;
        
    elseif n_flies_detected > n_arenas
        % Apply areasort to remove extra areas segmented
        im2 = areasort(im2, n_arenas);
        im2 = im2 > 0;
    end
    
    % Log the final arena
    arena_final(:,:,i) = uint8(single(im2) .* all_arenas_new);
    
    % Update progress bar
    textprogressbar(i/nframe2load*100);
end

% Terminate textprogressbar
textprogressbar('Done!')

%% Output workspace and the image if needed
% saveastiff(uint8(arena_final),'Michelletracking.tif');

save(fullfile(vidpath,[filename(1:end-4),'.mat']))

%% Obtain the coordinates of the flies
% Prime the matrix to store the coordinates
flycoords = zeros(n_arenas, 2, nframe2load);

% Initiate textprogressbar
textprogressbar('Determining centroids: ')

for ii = 1 : nframe2load
    % Obrain the centroids
    centroids = regionprops(arena_final(:,:,ii),'Centroid');
    
    % For mat the centroids and load it to the flycoords matrix
    flycoords(:,:,ii) = cell2mat({centroids.Centroid}');
    
    % Update text progress bar
    textprogressbar(i/nframe2load * 100);
end

% Terminate textprogressbar
textprogressbar('Done!')

%% Zero initial coordinate and make the plot
% Zero initial location
flycoords_zeroed = flycoords - repmat(flycoords(:,:,1),[1,1,nframe2load]);

% Plot the zeroed traces
figure('Position',[50, 200, 1500, 350], 'Color', [1 1 1])

% Left subplot shows the zeroed traces
subplot(1,4,1:3)
% plot(squeeze(flycoords_zeroed(:,1,:))' , squeeze(flycoords_zeroed(:,2,:))',...
%     'LineWidth', 2);

if flydirection == 1
    % Plot horizontal
    plot(squeeze(flycoords_zeroed(:,1,:))')
else
    % Plot vertical
    plot(squeeze(flycoords_zeroed(:,2,:))')
end

% Create lines to label quadrants
% ylimits = get(gca,'ylim');
% xlimits = get(gca,'xlim');

% line([0 0], ylimits, 'Color',[0 0 0])
% line(xlimits, [0 0], 'Color', [0 0 0])

% Label x and y
xlabel('Time (frame)')

if flydirection ==1
    ylabel('X location')
else
    ylabel('Y location')
end

% Right subplot shows the polar plot of the net displacement of each fly
subplot(1,4,4)
compass(flycoords_zeroed(:,:,end))

%% Print average summary plots

% Compute mean and sem
mean_coords = squeeze(nanmean(flycoords_zeroed,1));
semcoords = squeeze(nanstd(flycoords_zeroed,1) / sqrt(n_arenas));

% Plot mean
figure('color',[1 1 1]); 
% This part will differ based on whether flies are moving vertically or
% horizontally
shadedErrorBar((1:length(mean_coords(1,:)))/targetfps, mean_coords(1,:),...
    semcoords(1,:), {'Color', [0 .4 0.7]});
title('Mean Position', 'FontWeight', 'bold');
ylabel('Mean Position (pixels)');
xlabel('Time (seconds)');
set(gca,'Box','off');

% Compute mean velocity
diff_coords = diff(flycoords_zeroed,1,3);
mean_vel = squeeze(nanmean(diff_coords,1));
sem_vel = squeeze(nanstd(diff_coords,1) / sqrt(n_arenas));

% Plot mean velocity
figure('color',[1 1 1]); 
% This part will differ based on whether flies are moving vertically or
% horizontally
shadedErrorBar((1:length(mean_vel(1,:)))/targetfps, mean_vel(1,:),...
    sem_vel(1,:), {'Color', [0.5 0 0.5]});
title('Mean Velocity', 'FontWeight', 'bold');
ylabel('Velocity (pixels/frame)');
xlabel('Time (seconds)');
set(gca,'Box','off');

% Print out the number of nans in the computed array (as a sanity check on
% how good your thresholding was)
num_nans = sum(isnan(flycoords(:)));
display('Number of NaNs:'), display(num_nans);
%% Keep and save data
keep all_arena_size all_arenas_new arena_final flycoords flycoords_zeroed...
    filename n_arenas vidpath vidfps nframe2load
save(fullfile(vidpath,[filename(1:end-4),'_clean.mat']))
