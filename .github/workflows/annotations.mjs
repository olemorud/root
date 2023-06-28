#!/usr/bin/env node

import { Octokit } from 'octokit';

if (!process.env.GH_TOKEN) {
    console.error('Error: The GH_TOKEN environment variable is not set.');
    process.exit(1);
}

if (!process.env.workflow_id) {
    console.error('Error: The workflow_id environment variable is not set.');
    process.exit(1);
}

if (!process.env.GITHUB_REPOSITORY) {
    console.error('Error: The GITHUB_REPOSITORY environment variable is not set.');
    process.exit(1);
}

const octokit = new Octokit({ auth: process.env.GH_TOKEN });

// Get the jobs in the workflow ...
const { data: { jobs } } = await octokit.request(
    'GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs',
    {
        owner: process.env.GITHUB_REPOSITORY.split('/')[0],
        repo: process.env.GITHUB_REPOSITORY.split('/')[1],
        run_id: process.env.workflow_id,
        mediaType: {
            format: 'json',
            previews: ['scarlet-witch']
        }
    }
);

if ( !jobs ) {
    console.error(`Error: could not get jobs for repository ${ process.env.GITHUB_REPOSITORY }`)
}

console.log('run ids:', jobs.map(job => job.id));

// ... then get the annotations for each jobs
for (const job of jobs) {
    const { data: annotations } = await octokit.request(
        'GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations',
        {
            owner: process.env.GITHUB_REPOSITORY.split('/')[0],
            repo: process.env.GITHUB_REPOSITORY.split('/')[1],
            check_run_id: job.id,
            mediaType: {
                format: 'json',
                previews: ['scarlet-witch']
            }
        }
    );

    if ( !annotations ) {
        // this is not always a bug, could just be a run with no annotations
        console.info(`info: could not get annotations for data for run ${job.id}.`)
    }

    for (const an of annotations) {
        if (['warning', 'error'].includes(an.annotation_level.toLowerCase())) {
            console.log(an);
        }
    }
}