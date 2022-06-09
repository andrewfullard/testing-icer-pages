#!/bin/bash -login
#DESCRIPTION Easy checkpoint restart for long jobs
#LABEL PowerJobs
# Written by Dirk Colbry
#   This script works with the longjob powertool.
#
# Useful Enviornment Variables:
#   PBS_JOBSCRIPT - (REQUIRED) Name of the script that will get restarted (use $0 in most cases)
#   BLCR_WAIT_SEC - Time longjob will wait before checkpointing and restarting (DEFAULT 14100 seconds)
#   BLCR_OUTPUT - Filename to write standard error and standard output (DEFAULT output.txt)
#   BLCR_CHECKFILE - Name of the checkpoint file (DEFAULT checkfile.blcr)
#
# Usage (inside job script):
#   longjob programname arguments
#
# Special notes for job arrays:
#   longjob is written to work with job arrays.  However, users must be careful to check
#   and make sure that all files have unique names, including BLCR_OUTPUT and BLCR_CHECKFILE.
#   By default longjob will append ${PBS_ARRAYID} to the file names.
#
#   Since, by default, PBS appends the PBS_ARRAYID to the end of a job name, it is also
#   recommended that the PBS_JOBNAME be redivined in the script before running the longjob
#   command.  Ex:
#      PBS_JOBNAME=jobname #REQUIRED For job Arrays

export LANG=C

if [ "$#" = "0" ]
then
	echo "No Input arguments found"
	exit 1
fi

# Set the default wait time to just under four hours
if [ "${BLCR_WAIT_SEC}" = "" ]
then
	export BLCR_WAIT_SEC=$(( 4 * 60 * 60 - 5 * 60 ))
fi

#Name of the jobscript. Typically this can be set to $0 in the main script
if [ "${PBS_JOBSCRIPT}" = "" ]
then
	echo "ERROR - jobscript not found trying longjob.pbs"
	export PBS_JOBSCRIPT="longjob.pbs"
fi

#Name of the outputfile
if [ "${BLCR_OUTPUT}" = "" ]
then
	export BLCR_OUTPUT="output${PBS_ARRAYID}.txt"
fi

#Name of the Checkpoint file
if [ "${BLCR_CHECKFILE}" = "" ]
then
	export BLCR_CHECKFILE="checkfile${PBS_ARRAYID}.blcr"
fi

export checkpoint="${BLCR_CHECKFILE}"

#echo "BLCR_COUNT=${BLCR_COUNT}"
if [ ! -f ${checkpoint}  ]
then
	echo "Running for the first time"
        #Replace the program "supernova 1000" with your program and input arguments
	cr_run $* 1> ${BLCR_OUTPUT} 2>&1 &
	export PID=$!
	#export next=1
else
	echo "Restarting ${checkpoint}"

        #Job running as a restart job
	cr_restart --no-restore-pid ${checkpoint} >> ${BLCR_OUTPUT} 2>&1 &
	export PID=$!
	#export next=$(($BLCR_COUNT+1))
fi

#function to run if the program times out
checkpoint_timeout() {
  echo "Timeout. Checkpointing Job"

  dirtest=`echo $PWD | grep "scratch" | wc -l`

  if [ $dirtest -lt 1 ]
  then
	echo "WARNING: checkpoint file written to $PWD"
	echo ""
	echo "  For optimial performace, checkpoint files should be written to"
	echo "  /mnt/scratch space."
	echo ""
  fi

  time cr_checkpoint -v --term ${PID}

  if [ ! "$?" == "0" ]
  then
        echo "Failed to checkpoint"
        exit 2
  fi

  echo "Queueing Next Job"
  chmod 644 context.${PID}
  mv context.${PID} ${checkpoint}
  echo "qsub -t \"${PBS_ARRAYID}\" -N ${PBS_JOBNAME} ${PBS_JOBSCRIPT}"
  qsub -t "${PBS_ARRAYID}" -N ${PBS_JOBNAME} ${PBS_JOBSCRIPT}

  qstat -f ${PBS_JOBID} | grep "used"

  exit 0
}

#set checkpoint timeout
(sleep ${BLCR_WAIT_SEC}; echo 'Timer Done'; checkpoint_timeout;) &
timeout=$!
echo "starting timer (${timeout}) for ${BLCR_WAIT_SEC} seconds"

echo "Waiting on $PID"
wait ${PID}
RET=$?

#Check to see if job checkpointed
if [ "${RET}" = "143" ] #Job terminated due to cr_checkpoint
then
	echo "Job seems to have been checkpointed, waiting for checkpoint to complete."
	wait ${timeout}
	#qstat -f ${PBS_JOBID}
	exit 0
fi

## JOB completed

#Kill timeout timer
kill ${timeout}

#Email the user that the job has completed
#if [ "${BLCR_EMAIL}" = ""
if [ "${BLCR_EMAIL}" = "" -o "${BLCR_EMAIL}" = "TRUE" ]
then
	 qstat -f ${PBS_JOBID} | mail -s "JOB COMPLETE" ${USER}@msu.edu
fi
echo "Job completed with exit status ${RET}"
qstat -f ${PBS_JOBID} | grep "used"
export RET
#exit ${RET}
#exit 254