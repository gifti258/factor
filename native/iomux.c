#include "factor.h"

void init_io_tasks(fd_set* fdset, IO_TASK* io_tasks)
{
	int i;

	FD_ZERO(fdset);
	for(i = 0; i < FD_SETSIZE; i++)
	{
		io_tasks[i].port = F;
		io_tasks[i].callback = F;
	}
}

void init_iomux(void)
{
	read_fd_count = 0;
	init_io_tasks(&read_fd_set,read_io_tasks);

	write_fd_count = 0;
	init_io_tasks(&write_fd_set,write_io_tasks);
}

IO_TASK* add_io_task(
	IO_TASK_TYPE type,
	PORT* port,
	CELL callback,
	IO_TASK* io_tasks,
	int* fd_count)
{
	int fd = port->fd;

	/* if(io_tasks[fd].port != F)
		critical_error("Adding I/O task twice",fd); */

	io_tasks[fd].type = type;
	io_tasks[fd].port = tag_object(port);
	io_tasks[fd].callback = callback;

	if(fd >= *fd_count)
		*fd_count = fd + 1;

	return &io_tasks[fd];
}

void primitive_add_read_line_io_task(void)
{
	PORT* port = untag_port(dpop());
	CELL callback = dpop();
	add_io_task(IO_TASK_READ_LINE,port,callback,
		read_io_tasks,&read_fd_count);
}

void primitive_add_write_io_task(void)
{
	PORT* port = untag_port(dpop());
	CELL callback = dpop();
	add_io_task(IO_TASK_WRITE,port,callback,
		write_io_tasks,&write_fd_count);
}

void remove_io_task(
	IO_TASK_TYPE type,
	PORT* port,
	IO_TASK* io_tasks,
	int* fd_count)
{
	int fd = port->fd;

	io_tasks[fd].port = F;
	io_tasks[fd].callback = F;

	if(fd == *fd_count - 1)
		*fd_count = *fd_count - 1;
}

void remove_io_tasks(PORT* port)
{
	remove_io_task(IO_TASK_READ_LINE,port,
		read_io_tasks,&read_fd_count);
	remove_io_task(IO_TASK_WRITE,port,
		write_io_tasks,&write_fd_count);
}

bool set_up_fd_set(fd_set* fdset, int fd_count, IO_TASK* io_tasks)
{
	bool retval = false;
	int i;

	FD_ZERO(fdset);

	for(i = 0; i < fd_count; i++)
	{
		if(typep(PORT_TYPE,io_tasks[i].port))
		{
			retval = true;
			FD_SET(i,fdset);
		}
	}
	
	return retval;
}

bool perform_read_line_io_task(PORT* port)
{
	init_buffer(port,B_READ_LINE);
	if(port->buf_pos >= port->buf_fill)
	{
		if(!read_step(port))
			return false;
	}

	if(port->buf_fill == 0)
	{
		/* EOF */
		port->line = F;
		return true;
	}
	else
		return read_line_step(port);
}

bool perform_write_io_task(PORT* port)
{
	init_buffer(port,B_WRITE);
	if(write_step(port))
	{
		if(port->buf_pos == port->buf_fill)
		{
			/* All written */
			port->buf_pos = 0;
			port->buf_fill = 0;
			return true;
		}
	}
	return false;
}

CELL perform_io_task(IO_TASK* task)
{
	PORT* port = untag_port(task->port);
	CELL callback = task->callback;
	switch(task->type)
	{
	case IO_TASK_READ_LINE:
		remove_io_task(IO_TASK_READ_LINE,port,
			read_io_tasks,&read_fd_count);
		if(perform_read_line_io_task(port))
			return callback;
		else
		{
			add_io_task(IO_TASK_READ_LINE,port,
				callback,read_io_tasks,
				&read_fd_count);
			return F;
		}
	case IO_TASK_WRITE:
		remove_io_task(IO_TASK_WRITE,port,
			write_io_tasks,&write_fd_count);
		if(perform_write_io_task(port))
			return callback;
		else
		{
			add_io_task(IO_TASK_WRITE,port,
				callback,write_io_tasks,
				&write_fd_count);
			return F;
		}
	default:
		critical_error("Bad I/O task",task->type);
		return F;
	}
}

CELL perform_io_tasks(fd_set* fdset, int fd_count, IO_TASK* io_tasks)
{
	int i;
	CELL callback;

	for(i = 0; i < fd_count; i++)
	{
		if(FD_ISSET(i,fdset))
		{
			if(io_tasks[i].port == F)
				critical_error("select() returned fd for non-existent task",i);
			else
			{
				callback = perform_io_task(&io_tasks[i]);
				if(callback != F)
					return callback;
			}
		}
	}

	return F;
}

/* Wait for I/O and return a callback. */
CELL next_io_task(void)
{
	bool reading = set_up_fd_set(&read_fd_set,
		read_fd_count,read_io_tasks);
	bool writing = set_up_fd_set(&write_fd_set,
		write_fd_count,write_io_tasks);

	CELL callback;

	if(!reading && !writing)
		critical_error("next_io_task() called with no IO tasks",0);

	select(read_fd_count > write_fd_count
		? read_fd_count : write_fd_count,
		(reading ? &read_fd_set : NULL),
		(writing ? &write_fd_set : NULL),
		NULL,NULL);

	callback = perform_io_tasks(&read_fd_set,read_fd_count,read_io_tasks);
	if(callback != F)
		return callback;

	return perform_io_tasks(&write_fd_set,write_fd_count,write_io_tasks);
}

void primitive_next_io_task(void)
{
	dpush(next_io_task());
}

void collect_io_tasks(void)
{
	int i;

	for(i = 0; i < FD_SETSIZE; i++)
	{
		copy_object(&read_io_tasks[i].port);
		copy_object(&read_io_tasks[i].callback);
	}

	for(i = 0; i < FD_SETSIZE; i++)
	{
		copy_object(&write_io_tasks[i].port);
		copy_object(&write_io_tasks[i].callback);
	}
}
